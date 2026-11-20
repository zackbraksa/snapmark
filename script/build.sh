#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/ModuleCache}"
swift build --product Snapmark
BINARY="$(swift build --show-bin-path)/Snapmark"

BUNDLE="$ROOT_DIR/dist/Snapmark.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/Snapmark"
cp "$ROOT_DIR/Assets/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"

ICON_WORK="$(mktemp -d "${TMPDIR:-/tmp}/snapmark-icon.XXXXXX")"
trap 'rm -rf "$ICON_WORK"' EXIT
if xcrun actool "$ROOT_DIR/Assets/AppIcon.icon" \
    --compile "$ICON_WORK" --app-icon AppIcon --platform macosx \
    --minimum-deployment-target 14.0 \
    --output-partial-info-plist "$ICON_WORK/IconInfo.plist" \
    >"$ICON_WORK/build.log" 2>&1 && [ -f "$ICON_WORK/Assets.car" ]; then
    cp "$ICON_WORK/Assets.car" "$BUNDLE/Contents/Resources/Assets.car"
else
    rm -f "$BUNDLE/Contents/Resources/Assets.car"
    echo "Native icon compiler unavailable. Using the classic app icon."
fi

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Snapmark</string>
<key>CFBundleIdentifier</key><string>xyz.braksa.apps.snapmark.dev</string>
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
</dict></plist>
PLIST

codesign --force --sign "${SNAPMARK_SIGNING_IDENTITY:--}" --timestamp=none \
    --identifier xyz.braksa.apps.snapmark.dev "$BUNDLE"
codesign --verify --strict "$BUNDLE"
echo "Built $BUNDLE"
