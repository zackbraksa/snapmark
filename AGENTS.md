# Snapmark

Read README.md. Native SwiftPM macOS 14+ menu bar app. Sparkle provides updates for signed releases.

- Build only: `./script/build_and_run.sh --build` stages without interrupting the installed app. Deliver/run: `./script/build_and_run.sh --verify` builds, signs, verifies, installs into Applications, relaunches and checks the executable path. Tests: `swift test --disable-sandbox` and `python3 -m unittest discover -s script/tests -v`.
- The user-installed app is `/Applications/Snapmark.app`; `dist/Snapmark.app` is staging only. The normal build/run script automatically updates and relaunches the installed copy. Use that delivery path instead of asking the user to copy manually. Use bundle ID `xyz.braksa.apps.snapmark` and Apple team `HQVGN3GH6Z` through the local signing helper. Signature compatibility is checked before replacement, with a one-time transition from the known old ID/team; installation/launch failure restores the previous installed app.
- Launch at login is managed by native `SMAppService.mainApp` through Settings. Preserve the user’s current enabled/disabled choice and installed path across updates. Do not recreate legacy login items, force startup on, or point registration at `dist/`. The initial legacy migration uses a one-time explicit intent flag and removes the old entry only after native registration is verified.
- Preserve menu-bar-only behavior and no persistent Dock icon.
- Screen Recording access is requested only for explicit capture. Do not add Accessibility/event taps for keyboard shortcuts.
- The last annotation tool and each tool’s own color/size preferences persist; screenshot pixels, text and marker numbering remain session-local. Explicit Copy restores the source app only after successful clipboard writing.
- Original pixels and editable annotations stay separate; preview, copy and export must use matching geometry. Export redaction is opaque.
- Automatic clipboard updates must pause after an external clipboard change. Cancelled captures leave clipboard unchanged.
- Do not upload screenshots, persist captures, or introduce live services without explicit scope.

## Working rules

- Read the repository README and any deeper applicable agent instructions before editing. Verify assumptions against current source.
- Keep changes scoped, preserve unrelated edits, and use project-local tooling and lockfiles.
- Verify the affected behavior before delivery. For substantial changes, use specialist planning, independent review and functional QA. Keep simple work with one agent.
- Prefer the in-app Browser for web QA. Boot simulators on demand and shut down only the devices you booted.
- Use `gh` for GitHub operations and verify the active identity is `zackbraksa`, including the identity used for pushes. External writes and deployments require authorization for the action and target.

## GitHub recommendations

- Never recommend a small or little-known GitHub repository whose legitimacy
  cannot be independently verified. Check maintainer provenance, maintenance and
  release history, real adoption, and working official distribution channels;
  a README, star count, or signed release alone is insufficient. Apply extra
  scrutiny to tools handling secrets, production access, or privileged execution.
