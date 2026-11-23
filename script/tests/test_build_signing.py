import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


BUILD_SCRIPT = Path(__file__).resolve().parents[1] / "build_and_run.sh"
FIRST_IDENTITY = "1" * 40
SECOND_IDENTITY = "2" * 40
IDENTITIES = f'''  1) {FIRST_IDENTITY} "Apple Development: Example One (TEAMONE)"
  2) {SECOND_IDENTITY} "Apple Development: Example Two (TEAMTWO)"
     2 valid identities found
'''
STUB = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

command = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["SNAPMARK_TEST_CALLS"], "a") as log:
    log.write(json.dumps([command, *args]) + "\n")
state_path = Path(os.environ["SNAPMARK_TEST_STATE"])
state = json.loads(state_path.read_text())
failure = os.environ.get("SNAPMARK_TEST_FAILURE")
if command == "security":
    print(os.environ["SNAPMARK_TEST_IDENTITIES"])
elif command == "swift":
    if failure == "build":
        sys.exit(1)
    if "--show-bin-path" in args:
        print(os.environ["SNAPMARK_TEST_BINARY_DIR"])
elif command == "xcrun":
    assert args[0] == "actool"
    source = Path(args[1])
    assert source.is_absolute() and (source / "icon.json").exists()
    for flag, value in (("--app-icon", "AppIcon"), ("--platform", "macosx"),
                        ("--minimum-deployment-target", "14.0")):
        assert args[args.index(flag) + 1] == value
    if failure == "icon":
        sys.exit(1)
    output = Path(args[args.index("--compile") + 1])
    (output / "Assets.car").write_bytes(b"test adaptive icon")
    Path(args[args.index("--output-partial-info-plist") + 1]).write_text("<plist/>")
elif command == "codesign":
    if "-R" in args:
        assert args[args.index("-R") + 1].startswith("=identifier ")
        if failure == "identity":
            sys.exit(1)
    if "--sign" in args:
        icon = Path(args[-1]) / "Contents" / "Resources" / "AppIcon.icns"
        assert icon.read_bytes() == b"test app icon"
        adaptive_icon = icon.parent / "Assets.car"
        assert adaptive_icon.read_bytes() == b"test adaptive icon"
        if failure == "sign":
            sys.exit(1)
    elif "--verify" in args and failure == "verify":
        sys.exit(1)
    elif "-d" in args:
        if "-r-" in args:
            print('designated => identifier "xyz.braksa.apps.snapmark"', file=sys.stderr)
    if "-dv" in args:
        with (Path(args[-1]) / "Contents" / "Info.plist").open("rb") as source:
            identifier = plistlib.load(source)["CFBundleIdentifier"]
        team = os.environ.get("SNAPMARK_TEST_INSTALLED_TEAM", "7LQMTS9FZ5") if identifier == "xyz.braksa.snapmark" else "HQVGN3GH6Z"
        if failure == "team":
            team = "WRONGTEAM1"
        print("TeamIdentifier=" + team, file=sys.stderr)
elif command == "ditto":
    if failure == "copy":
        sys.exit(1)
    shutil.copytree(args[-2], args[-1], dirs_exist_ok=True)
elif command == "mv":
    destination = Path(args[-1])
    if failure == "install" and destination == Path(os.environ["SNAPMARK_INSTALL_DIR"]) / "Snapmark.app" and "backup" not in str(args[-2]).lower():
        sys.exit(1)
    if failure == "backup" and destination.name == "Backup.app":
        sys.exit(1)
    sys.exit(subprocess.run(["/bin/mv", *args]).returncode)
elif command == "pgrep":
    if not state["running"]:
        sys.exit(1)
    print("424242")
elif command == "pkill":
    state["running"] = False
    state_path.write_text(json.dumps(state))
elif command == "open":
    state["running"] = True
    state["path"] = str(Path(args[-1]) / "Contents" / "MacOS" / "Snapmark")
    if failure == "wrong-launch":
        state["path"] = "/some/other/Snapmark.app/Contents/MacOS/Snapmark"
    state_path.write_text(json.dumps(state))
elif command == "ps":
    print(state["path"])
elif command == "lldb":
    sys.exit(1 if failure == "debug" else 0)
'''


class BuildSigningTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="snapmark-signing-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "snapmark"
        (self.root / "script").mkdir(parents=True)
        (self.root / "script" / "apple-development-identity.py").write_text(
            "import os,sys\n"
            "assert sys.argv[1:] == ['--team', 'HQVGN3GH6Z']\n"
            "if os.environ['SNAPMARK_TEST_IDENTITIES'] == '0 valid identities found': sys.exit(1)\n"
            "print(os.environ.get('SNAPMARK_TEST_SELECTED_IDENTITY', '" + FIRST_IDENTITY + "'))\n")
        (self.root / "script" / "macos-sparkle.py").write_text(
            "import json,os,sys\n"
            "from pathlib import Path\n"
            "assert sys.argv[1] == 'embed' and Path(sys.argv[2]).resolve() == Path.cwd() / 'dist/Snapmark.app' and Path(sys.argv[3]).resolve() == Path.cwd() / '.build'\n"
            "with open(os.environ['SNAPMARK_TEST_CALLS'], 'a') as log: log.write(json.dumps(['sparkle-embed', *sys.argv[1:]]) + '\\n')\n")
        self.script = self.root / "script" / "build_and_run.sh"
        shutil.copy2(BUILD_SCRIPT, self.script)
        (self.root / "Assets").mkdir()
        (self.root / "Assets" / "AppIcon.icns").write_bytes(b"test app icon")
        (self.root / "Assets" / "AppIcon.icon").mkdir()
        (self.root / "Assets" / "AppIcon.icon" / "icon.json").write_text("{}")
        self.commands = self.root / "commands"
        self.commands.mkdir()
        for command in ("swift", "xcrun", "security", "codesign", "ditto", "mv",
                        "pgrep", "pkill", "open", "ps", "sleep", "lldb"):
            stub = self.commands / command
            stub.write_text(STUB)
            stub.chmod(0o755)
        self.binary_directory = self.root / "binary"
        self.binary_directory.mkdir()
        (self.binary_directory / "Snapmark").write_bytes(b"new executable")
        self.calls_file = self.root / "calls.jsonl"
        self.install_directory = self.root / "Applications"
        self.install_directory.mkdir()
        self.installed_bundle = self.install_directory / "Snapmark.app"
        self.state_file = self.root / "state.json"
        self.state_file.write_text(json.dumps({"running": True, "path": str(
            self.installed_bundle / "Contents" / "MacOS" / "Snapmark")}))
        self.environment = dict(os.environ)
        self.environment.pop("SNAPMARK_SIGNING_IDENTITY", None)
        self.environment.update({
            "PATH": f"{self.commands}:{os.environ['PATH']}",
            "SNAPMARK_TEST_CALLS": str(self.calls_file),
            "SNAPMARK_TEST_STATE": str(self.state_file),
            "SNAPMARK_INSTALL_DIR": str(self.install_directory),
            "SNAPMARK_TEST_BINARY_DIR": str(self.binary_directory),
            "SNAPMARK_TEST_IDENTITIES": IDENTITIES,
        })

    def run_build(self, mode="--build"):
        arguments = ["/bin/bash", str(self.script)]
        if mode is not None:
            arguments.append(mode)
        return subprocess.run(arguments,
                              env=self.environment, capture_output=True, text=True, timeout=60)

    def calls(self, command):
        if not self.calls_file.exists():
            return []
        return [call for line in self.calls_file.read_text().splitlines()
                if (call := json.loads(line))[0] == command]

    def signing_identity(self):
        signing_calls = [call for call in self.calls("codesign") if "--sign" in call]
        self.assertEqual(len(signing_calls), 1)
        call = signing_calls[0]
        return call[call.index("--sign") + 1]

    def test_signing_uses_team_helper_identity(self):
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.signing_identity(), FIRST_IDENTITY)
        contents = self.root / "dist" / "Snapmark.app" / "Contents"
        self.assertEqual((contents / "Resources" / "AppIcon.icns").read_bytes(),
                         b"test app icon")
        self.assertEqual((contents / "Resources" / "Assets.car").read_bytes(),
                         b"test adaptive icon")
        with (contents / "Info.plist").open("rb") as plist:
            metadata = plistlib.load(plist)
        self.assertEqual(metadata["CFBundleIconFile"], "AppIcon")
        self.assertEqual(metadata["CFBundleIconName"], "AppIcon")
        self.assertEqual(metadata["CFBundleIdentifier"], "xyz.braksa.apps.snapmark")
        self.assertIs(metadata["SparkleUpdatesEnabled"], False)
        calls = [json.loads(line) for line in self.calls_file.read_text().splitlines()]
        compile_index = next(i for i, call in enumerate(calls) if call[0] == "xcrun")
        sign_index = next(i for i, call in enumerate(calls)
                          if call[0] == "codesign" and "--sign" in call)
        embed_index = next(i for i, call in enumerate(calls) if call[0] == "sparkle-embed")
        self.assertLess(compile_index, embed_index)
        self.assertLess(embed_index, sign_index)

    def test_helper_selected_identity_is_used(self):
        self.environment["SNAPMARK_TEST_SELECTED_IDENTITY"] = SECOND_IDENTITY
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.signing_identity(), SECOND_IDENTITY)

    def test_missing_certificate_preserves_existing_bundle(self):
        self.environment["SNAPMARK_TEST_IDENTITIES"] = "0 valid identities found"
        executable = self.root / "dist" / "Snapmark.app" / "Contents" / "MacOS" / "Snapmark"
        executable.parent.mkdir(parents=True)
        executable.write_bytes(b"previous signed executable")
        plist = executable.parent.parent / "Info.plist"
        plist.write_bytes(b"previous bundle metadata")
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(executable.read_bytes(), b"previous signed executable")
        self.assertEqual(plist.read_bytes(), b"previous bundle metadata")
        self.assertEqual(self.calls("codesign"), [])

    def test_wrong_signed_team_is_rejected(self):
        self.environment["SNAPMARK_TEST_FAILURE"] = "team"
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls("open"), [])

    def seed_installed_bundle(self, identifier="xyz.braksa.apps.snapmark"):

        executable = self.installed_bundle / "Contents" / "MacOS" / "Snapmark"
        executable.parent.mkdir(parents=True)
        executable.write_bytes(b"previous installed executable")
        with (executable.parent.parent / "Info.plist").open("wb") as target:
            plistlib.dump({"CFBundleIdentifier": identifier}, target)
        resource = self.installed_bundle / "Contents" / "Resources" / "stale.txt"
        resource.parent.mkdir()
        resource.write_text("stale resource")
        return executable, resource

    def assert_installed_untouched(self, executable, resource):
        self.assertEqual(executable.read_bytes(), b"previous installed executable")
        self.assertEqual(resource.read_text(), "stale resource")
        self.assertTrue(json.loads(self.state_file.read_text())["running"])
        self.assertEqual(self.calls("pkill"), [])
        self.assertEqual(self.calls("open"), [])

    def test_default_run_replaces_installed_bundle_and_launches_installed_path(self):
        executable, stale_resource = self.seed_installed_bundle()
        result = self.run_build(mode=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(executable.read_bytes(), b"new executable")
        self.assertFalse(stale_resource.exists())
        self.assertEqual((self.installed_bundle / "Contents" / "Resources" /
                          "AppIcon.icns").read_bytes(), b"test app icon")
        self.assertEqual(len(self.calls("open")), 1)
        self.assertEqual(self.calls("open")[0][-1], str(self.installed_bundle))
        self.assertEqual(json.loads(self.state_file.read_text())["path"], str(executable))
        self.assertTrue(self.calls("ps"))
        self.assertTrue(self.calls("pkill"))
        self.assertIn("-u", self.calls("pkill")[0])
        self.assertIn("-x", self.calls("pkill")[0])
        calls = [json.loads(line) for line in self.calls_file.read_text().splitlines()]
        stop_index = next(i for i, call in enumerate(calls) if call[0] == "pkill")
        candidate_verifies = [i for i, call in enumerate(calls)
                              if call[0] == "codesign" and "--verify" in call
                              and call[-1] != str(self.root / "dist" / "Snapmark.app")]
        self.assertTrue(any(i < stop_index for i in candidate_verifies),
                        "The install candidate must be verified before stopping Snapmark")

    def test_known_old_identity_can_be_replaced(self):
        executable, _ = self.seed_installed_bundle("xyz.braksa.snapmark")
        result = self.run_build(mode=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(executable.read_bytes(), b"new executable")
        self.assertFalse(any("-R" in call for call in self.calls("codesign")))

    def test_old_identifier_with_wrong_team_is_left_untouched(self):
        executable, resource = self.seed_installed_bundle("xyz.braksa.snapmark")
        self.environment["SNAPMARK_TEST_INSTALLED_TEAM"] = "WRONGTEAM1"
        result = self.run_build(mode=None)
        self.assertNotEqual(result.returncode, 0)
        self.assert_installed_untouched(executable, resource)

    def test_unknown_installed_identity_is_left_untouched(self):
        executable, resource = self.seed_installed_bundle("xyz.other.app")
        result = self.run_build(mode=None)
        self.assertNotEqual(result.returncode, 0)
        self.assert_installed_untouched(executable, resource)

    def test_build_only_does_not_modify_or_launch_installed_bundle(self):
        executable, resource = self.seed_installed_bundle()
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_installed_untouched(executable, resource)
        self.assertEqual(self.calls("ditto"), [])
        self.assertEqual(self.calls("mv"), [])

    def test_failed_build_signing_or_verification_preserves_running_install(self):
        executable, resource = self.seed_installed_bundle()
        for failure in ("build", "icon", "sign", "verify", "copy", "identity"):
            with self.subTest(failure=failure):
                self.environment["SNAPMARK_TEST_FAILURE"] = failure
                self.calls_file.unlink(missing_ok=True)
                result = self.run_build(mode=None)
                self.assertNotEqual(result.returncode, 0)
                self.assert_installed_untouched(executable, resource)

    def test_failed_icon_compilation_preserves_existing_staging_bundle(self):
        executable, resource = self.seed_installed_bundle()
        staged = self.root / "dist" / "Snapmark.app" / "Contents"
        (staged / "MacOS").mkdir(parents=True)
        (staged / "MacOS" / "Snapmark").write_bytes(b"previous staged executable")
        (staged / "Info.plist").write_bytes(b"previous staged metadata")
        self.environment["SNAPMARK_TEST_FAILURE"] = "icon"
        result = self.run_build(mode=None)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((staged / "MacOS" / "Snapmark").read_bytes(),
                         b"previous staged executable")
        self.assertEqual((staged / "Info.plist").read_bytes(), b"previous staged metadata")
        self.assertEqual(self.calls("codesign"), [])
        self.assert_installed_untouched(executable, resource)

    def test_failed_install_restores_previous_bundle(self):
        executable, resource = self.seed_installed_bundle()
        self.environment["SNAPMARK_TEST_FAILURE"] = "install"
        result = self.run_build(mode=None)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(executable.read_bytes(), b"previous installed executable")
        self.assertEqual(resource.read_text(), "stale resource")

    def test_failed_backup_move_restarts_previous_bundle(self):
        executable, resource = self.seed_installed_bundle()
        self.environment["SNAPMARK_TEST_FAILURE"] = "backup"
        result = self.run_build(mode=None)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(executable.read_bytes(), b"previous installed executable")
        self.assertEqual(resource.read_text(), "stale resource")
        self.assertTrue(json.loads(self.state_file.read_text())["running"])
        self.assertTrue(self.calls("pkill"))
        self.assertEqual(self.calls("open")[-1][-1], str(self.installed_bundle))

    def test_failed_debugger_restores_and_restarts_previous_bundle(self):
        executable, resource = self.seed_installed_bundle()
        self.environment["SNAPMARK_TEST_FAILURE"] = "debug"
        result = self.run_build(mode="--debug")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(executable.read_bytes(), b"previous installed executable")
        self.assertEqual(resource.read_text(), "stale resource")
        self.assertTrue(json.loads(self.state_file.read_text())["running"])
        self.assertEqual(self.calls("lldb")[0][-1], str(executable))
        self.assertEqual(self.calls("open")[-1][-1], str(self.installed_bundle))

    def test_verify_rejects_process_running_from_another_path(self):
        self.seed_installed_bundle()
        self.environment["SNAPMARK_TEST_FAILURE"] = "wrong-launch"
        result = self.run_build(mode="--verify")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.calls("ps"))


if __name__ == "__main__":
    unittest.main()
