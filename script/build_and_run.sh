#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--build|--verify|--debug|--logs|--telemetry) ;; *) echo "usage: $0 [--build|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;; esac
SIGNING_TEAM="HQVGN3GH6Z"
SIGNING_IDENTITY="$(python3 "$ROOT_DIR/script/apple-development-identity.py" --team "$SIGNING_TEAM")"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/ModuleCache}"
swift build --build-system native --disable-sandbox --product Snapmark
BINARY="$(swift build --build-system native --disable-sandbox --show-bin-path)/Snapmark"
ICON_WORK="$(mktemp -d "${TMPDIR:-/tmp}/snapmark-adaptive-icon.XXXXXX")"
trap 'rm -rf "$ICON_WORK"' EXIT
xcrun actool "$ROOT_DIR/Assets/AppIcon.icon" --compile "$ICON_WORK" --app-icon AppIcon --platform macosx --minimum-deployment-target 14.0 --output-partial-info-plist "$ICON_WORK/IconInfo.plist"
BUNDLE="$ROOT_DIR/dist/Snapmark.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/Snapmark"
cp "$ROOT_DIR/Assets/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ICON_WORK/Assets.car" "$BUNDLE/Contents/Resources/Assets.car"
rm -rf "$ICON_WORK"
trap - EXIT
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Snapmark</string>
<key>CFBundleIdentifier</key><string>xyz.braksa.apps.snapmark</string>
<key>CFBundleName</key><string>Snapmark</string>
<key>CFBundleDisplayName</key><string>Snapmark</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSScreenCaptureUsageDescription</key><string>Snapmark captures a screen, window, or area when you request a screenshot.</string>
<key>NSHighResolutionCapable</key><true/>
<key>SparkleUpdatesEnabled</key><false/>
</dict></plist>
PLIST
python3 "$ROOT_DIR/script/macos-sparkle.py" embed "$BUNDLE" "$ROOT_DIR/.build"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none --identifier xyz.braksa.apps.snapmark "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
BUILT_TEAM="$(codesign -dv "$BUNDLE" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [ "$BUILT_TEAM" != "$SIGNING_TEAM" ]; then
  echo "Snapmark must be signed by team $SIGNING_TEAM; found $BUILT_TEAM." >&2
  exit 1
fi
if [ "$MODE" = --build ]; then exit 0; fi

INSTALL_DIR="${SNAPMARK_INSTALL_DIR:-/Applications}"
case "$INSTALL_DIR" in /*) ;; *) echo "SNAPMARK_INSTALL_DIR must be an absolute path." >&2; exit 1 ;; esac
INSTALLED_BUNDLE="$INSTALL_DIR/Snapmark.app"
USER_ID="$(id -u)"
if [ -e "$INSTALLED_BUNDLE" ]; then
  INSTALLED_ID="$(python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1], "rb"))["CFBundleIdentifier"])' "$INSTALLED_BUNDLE/Contents/Info.plist")"
  if [ "$INSTALLED_ID" = xyz.braksa.snapmark ]; then
    codesign --verify --deep --strict "$INSTALLED_BUNDLE"
    INSTALLED_TEAM="$(codesign -dv "$INSTALLED_BUNDLE" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
    if [ "$INSTALLED_TEAM" != 7LQMTS9FZ5 ]; then
      echo "The old Snapmark identity does not belong to its expected team; leaving it unchanged." >&2
      exit 1
    fi
  elif [ "$INSTALLED_ID" = xyz.braksa.apps.snapmark ]; then
    REQUIREMENT="$(codesign -d -r- "$INSTALLED_BUNDLE" 2>&1 | sed -n 's/^designated => //p')"
    if [ -z "$REQUIREMENT" ]; then
      echo "Cannot read the installed app's signing identity; leaving it unchanged." >&2
      exit 1
    fi
    codesign --verify --deep --strict -R "=$REQUIREMENT" "$BUNDLE"
  else
    echo "The installed bundle is not a known Snapmark identity; leaving it unchanged." >&2
    exit 1
  fi
fi

mkdir -p "$INSTALL_DIR"
INSTALL_WORK="$(mktemp -d "$INSTALL_DIR/.Snapmark-install.XXXXXX")"
BACKUP_BUNDLE="$INSTALL_WORK/Backup.app"
COMMITTED=false
WAS_RUNNING=false
cleanup() {
  local result=$?
  trap - EXIT
  if [ "$COMMITTED" = false ] && [ -e "$BACKUP_BUNDLE" ]; then
    pkill -u "$USER_ID" -x Snapmark >/dev/null 2>&1 || true
    if [ -e "$INSTALLED_BUNDLE" ] && ! mv "$INSTALLED_BUNDLE" "$INSTALL_WORK/Failed.app"; then
      echo "Could not restore Snapmark. Previous app retained at $BACKUP_BUNDLE" >&2
      exit "$result"
    fi
    if ! mv "$BACKUP_BUNDLE" "$INSTALLED_BUNDLE"; then
      echo "Could not restore Snapmark. Previous app retained at $BACKUP_BUNDLE" >&2
      exit "$result"
    fi
  fi
  if [ "$COMMITTED" = false ] && [ "$WAS_RUNNING" = true ] && [ -e "$INSTALLED_BUNDLE" ] && ! pgrep -u "$USER_ID" -x Snapmark >/dev/null; then
    open -n "$INSTALLED_BUNDLE" || true
  fi
  rm -rf "$INSTALL_WORK"
  exit "$result"
}
trap cleanup EXIT

ditto "$BUNDLE" "$INSTALL_WORK/New.app"
codesign --verify --deep --strict "$INSTALL_WORK/New.app"
if pgrep -u "$USER_ID" -x Snapmark >/dev/null; then
  WAS_RUNNING=true
  pkill -u "$USER_ID" -x Snapmark
  for attempt in {1..50}; do
    if ! pgrep -u "$USER_ID" -x Snapmark >/dev/null; then break; fi
    sleep 0.1
  done
  if pgrep -u "$USER_ID" -x Snapmark >/dev/null; then
    echo "Snapmark did not quit; leaving the installed app unchanged." >&2
    exit 1
  fi
fi
if [ -e "$INSTALLED_BUNDLE" ]; then mv "$INSTALLED_BUNDLE" "$BACKUP_BUNDLE"; fi
mv "$INSTALL_WORK/New.app" "$INSTALLED_BUNDLE"
codesign --verify --deep --strict "$INSTALLED_BUNDLE"

verify_running() {
  local pid executable
  for attempt in {1..50}; do
    while IFS= read -r pid; do
      executable="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
      if [ "$executable" = "$INSTALLED_BUNDLE/Contents/MacOS/Snapmark" ]; then return 0; fi
    done < <(pgrep -u "$USER_ID" -x Snapmark || true)
    sleep 0.1
  done
  echo "Snapmark did not launch from $INSTALLED_BUNDLE." >&2
  return 1
}

if [ "$MODE" = --debug ]; then
  lldb -- "$INSTALLED_BUNDLE/Contents/MacOS/Snapmark"
  COMMITTED=true
else
  open -n "$INSTALLED_BUNDLE"
  verify_running
  COMMITTED=true
  echo "Updated and launched $INSTALLED_BUNDLE"
  case "$MODE" in
    --logs) /usr/bin/log stream --info --style compact --predicate 'process == "Snapmark"' ;;
    --telemetry) /usr/bin/log stream --info --style compact --predicate 'subsystem == "xyz.braksa.snapmark"' ;;
  esac
fi
