#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
./script/build.sh
swift build --configuration release --arch arm64 --arch x86_64 --product Snapmark
binary="$(swift build --configuration release --arch arm64 --arch x86_64 --show-bin-path)/Snapmark"
staging="$(mktemp -d "${TMPDIR:-/tmp}/snapmark-release-resources.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto dist/Snapmark.app "$staging/Snapmark.app"
cp LICENSE "$staging/Snapmark.app/Contents/Resources/LICENSE"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier xyz.braksa.apps.snapmark' "$staging/Snapmark.app/Contents/Info.plist"
public_key="$(python3 -c 'import json; print(json.load(open("release-config.json"))["sparklePublicKey"])')"
python3 script/macos-sparkle.py prepare-release "$staging/Snapmark.app" "$binary" release-config.json "$public_key" dist/release/Snapmark.app
