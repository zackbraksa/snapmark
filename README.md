<p align="center">
  <img src="Assets/AppIcon.icon/Assets/Foreground.png" alt="" width="144" height="144">
</p>
<h1 align="center">Snapmark</h1>
<p align="center"><strong>Capture, annotate, and paste from your Mac menu bar.</strong></p>
<p align="center">
  <strong><a href="https://github.com/zackbraksa/snapmark/releases/download/v0.1.1/Snapmark-0.1.1-macOS.dmg">Download Snapmark for macOS</a></strong><br>
  macOS 14 or later · Apple silicon and Intel
</p>

Open the disk image and drag **Snapmark** to **Applications**. Allow Screen Recording when macOS asks on your first capture.

![Snapmark annotates a sample project board with an arrow, rectangle, and numbered marker](docs/screenshots/snapmark-demo.png)

Grab an area, a window, or the whole screen. Mark up what matters with arrows, shapes, text, and numbered steps. Copy the result straight into a message or save it as a PNG.

Snapmark works locally. It keeps the current screenshot in memory and updates your clipboard as you edit. Use solid redaction to cover sensitive pixels in the exported image.

Signed releases include **Check for Updates…** in the menu bar menu. Existing users need to install this release once to receive future updates automatically.

## Annotate

Choose a tool in the top toolbar. The options row shows the color, size, or text controls for that tool. Choose Text, type your annotation, then click the screenshot to place it. Use Select to move annotations and drag the bottom-right handle to resize them.

The bottom bar shows image dimensions and clipboard or save status. Use Fit to fit the image to the window, Save PNG to export it, or Copy & Close to return to the app you captured from.

## Build from source

You’ll need macOS 14 or later and Xcode 26 or later.

```sh
git clone https://github.com/zackbraksa/snapmark.git
cd snapmark
./script/build.sh
open dist/Snapmark.app
```

The script builds a separate development app in `dist/`. An ad hoc-signed development build may need Screen Recording permission again after a rebuild.

If you have a signing identity in your Keychain, set `SNAPMARK_SIGNING_IDENTITY` when building to keep the app’s signing identity stable.

## Default shortcuts

| Action | Shortcut |
| --- | --- |
| Capture an area | <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>A</kbd> |
| Capture a window | <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>W</kbd> |
| Capture the full screen | <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>S</kbd> |
| Copy and close the editor | <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>C</kbd> |

Change any shortcut in Snapmark Settings.

## Tests

```sh
swift test --build-system native
```

## License

[MIT](LICENSE)

## Release preparation

The release configuration keeps the public Sparkle key, feed URL, and monotonically increasing build number. The private Sparkle key remains in Keychain. With `MACOS_SIGNING_IDENTITY` set to the matching Developer ID Application identity, run `./script/prepare-release.sh` to create a separate universal signed candidate in `dist/release/`. Notarize and staple the app and its DMG before publishing. Generate the appcast from the final DMG using the configured Sparkle Keychain account.
