#!/usr/bin/env python3
"""Bundle Sparkle and prepare a separate Developer ID release candidate."""

import argparse
import base64
import binascii
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from urllib.parse import urlsplit


def run(*args):
    subprocess.run(args, check=True)


def embed(app, scratch):
    artifact = scratch / 'artifacts/sparkle/Sparkle'
    framework = artifact / 'Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
    notice = artifact / 'LICENSE'
    if not framework.is_dir() or not notice.is_file():
        raise ValueError(f'Sparkle framework or license missing from {artifact}')

    frameworks = app / 'Contents/Frameworks'
    resources = app / 'Contents/Resources'
    frameworks.mkdir(parents=True, exist_ok=True)
    resources.mkdir(parents=True, exist_ok=True)
    destination = frameworks / framework.name
    with tempfile.TemporaryDirectory(dir=frameworks) as temporary:
        staged = Path(temporary) / framework.name
        run('/usr/bin/ditto', framework, staged)
        if destination.exists():
            shutil.rmtree(destination)
        staged.rename(destination)
    shutil.copyfile(notice, resources / 'SPARKLE-LICENSE.txt')


def release_info(info, config, public_key):
    feed = urlsplit(config['feedURL'])
    if feed.scheme != 'https' or not feed.hostname or feed.username is not None:
        raise ValueError('Release feed must be a public HTTPS URL')
    try:
        key = base64.b64decode(public_key, validate=True)
    except binascii.Error as error:
        raise ValueError('Sparkle public key must be base64') from error
    if len(key) != 32:
        raise ValueError('Sparkle public key must decode to 32 bytes')
    if info['CFBundleIdentifier'] != config['bundleIdentifier']:
        raise ValueError('App bundle identifier does not match the release configuration')
    if not isinstance(config['build'], int) or config['build'] <= int(info['CFBundleVersion']):
        raise ValueError('Release build must exceed the input bundle build number')

    return {
        **info,
        'CFBundleShortVersionString': config['version'],
        'CFBundleVersion': str(config['build']),
        'SparkleUpdatesEnabled': True,
        'SUFeedURL': config['feedURL'],
        'SUPublicEDKey': public_key,
    }


def sign_release(app, identity):
    framework = app / 'Contents/Frameworks/Sparkle.framework'
    version = (framework / 'Versions/Current').resolve(strict=True)
    helpers = [path for path in version.rglob('*') if path.is_dir() and path.suffix in ('.app', '.xpc')]
    autoupdate = version / 'Autoupdate'
    if autoupdate.is_file():
        helpers.append(autoupdate)
    for path in [*sorted(helpers, key=lambda path: len(path.parts), reverse=True), framework, app]:
        run('/usr/bin/codesign', '--force', '--options', 'runtime', '--timestamp', '--sign', identity, path)
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)


def prepare_release(args):
    identity = os.environ.get('MACOS_SIGNING_IDENTITY', '')
    if not identity.startswith('Developer ID Application:'):
        raise ValueError('Set MACOS_SIGNING_IDENTITY to a Developer ID Application identity')
    if args.output.exists() or args.output.is_symlink() or args.output.suffix != '.app':
        raise ValueError('Provide a new .app output path')

    info = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())
    config = json.loads(args.config.read_bytes())
    info = release_info(info, config, args.public_key)
    for architecture in ('arm64', 'x86_64'):
        run('/usr/bin/lipo', '-verify_arch', architecture, args.binary)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.output.parent) as temporary:
        staged = Path(temporary) / args.output.name
        run('/usr/bin/ditto', args.app, staged)
        executable = staged / 'Contents/MacOS' / info['CFBundleExecutable']
        shutil.copy2(args.binary, executable)
        (staged / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        sign_release(staged, identity)
        run(
            '/usr/bin/codesign', '--verify', '--strict',
            '-R', f'=anchor apple generic and certificate leaf[subject.OU] = "{config["teamIdentifier"]}"',
            staged,
        )
        staged.rename(args.output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    bundle = commands.add_parser('embed', help='copy the resolved Sparkle framework and license')
    bundle.add_argument('app', type=Path)
    bundle.add_argument('scratch', type=Path)
    release = commands.add_parser('prepare-release', help='sign a separate universal release candidate')
    release.add_argument('app', type=Path, help='development bundle containing resources and Sparkle')
    release.add_argument('binary', type=Path, help='universal SwiftPM release executable')
    release.add_argument('config', type=Path)
    release.add_argument('public_key', help='base64 Sparkle public key')
    release.add_argument('output', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'embed':
            embed(args.app, args.scratch)
        else:
            prepare_release(args)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Sparkle packaging: {error}\n')


if __name__ == '__main__':
    main()
