import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let shortcuts: ShortcutStore
    let launchAtLogin: LaunchAtLoginStore
    @AppStorage("automaticCopy") private var automaticCopy = true
    @State private var recording: ShortcutAction?
    @State private var validationMessage: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if launchAtLogin.status == .requiresApproval {
                    Text("Launch at login needs your approval in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings") { launchAtLogin.openLoginItemsSettings() }
                }
                if let error = launchAtLogin.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Capture") {
                Toggle("Keep clipboard updated", isOn: $automaticCopy)
                Text("Copies captures and completed edits automatically. Pauses if another app changes the clipboard; use Copy in the editor to resume.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Keyboard Shortcuts") {
                ForEach(ShortcutAction.allCases) { action in
                    shortcutRow(action)
                }
                if let validationMessage {
                    Text(validationMessage).font(.caption).foregroundStyle(.red)
                }
                Text("Click a shortcut, then press a key with Command, Option, or Control. Press Escape to cancel. Copy works while the editor is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Defaults use ⌃⌥⌘ with A for area, W for window, S for full screen, and C for copy. If another app uses one of these shortcuts, choose a different shortcut here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Open Keyboard Settings", destination: URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            if recording != nil {
                ShortcutRecorder { event in record(event) }
                    .frame(width: 0, height: 0)
            }
        }
        .onDisappear { stopRecording() }
        .onAppear { launchAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if recording != nil { stopRecording() }
        }
    }

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(action.title)
                Spacer()
                Button(recording == action ? "Press shortcut…" : shortcuts.display(for: action)) {
                    validationMessage = nil
                    recording = action
                    shortcuts.setRecording(true)
                }
                .frame(minWidth: 110)
                .accessibilityLabel("Record shortcut for \(action.title)")
                Button("Clear") {
                    stopRecording()
                    validationMessage = shortcuts.set(nil, for: action)
                }
                .disabled(shortcuts.binding(for: action) == nil)
                Button("Reset") {
                    stopRecording()
                    validationMessage = shortcuts.reset(action)
                }
                .help("Restore the default shortcut")
            }
            if let error = shortcuts.registrationErrors[action] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func record(_ event: NSEvent) {
        guard let action = recording else { return }
        if event.keyCode == 53 { stopRecording(); return }
        let binding = ShortcutBinding(keyCode: event.keyCode, modifiers: event.modifierFlags)
        if let error = shortcuts.set(binding, for: action) {
            validationMessage = error
        } else {
            validationMessage = nil
            stopRecording()
        }
    }

    private func stopRecording() {
        recording = nil
        shortcuts.setRecording(false)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let onKey: (NSEvent) -> Void
    func makeNSView(context: Context) -> RecordingView { RecordingView(onKey: onKey) }
    func updateNSView(_ view: RecordingView, context: Context) {
        view.onKey = onKey
        if view.window?.firstResponder !== view { view.window?.makeFirstResponder(view) }
    }

    final class RecordingView: NSView {
        var onKey: (NSEvent) -> Void
        init(onKey: @escaping (NSEvent) -> Void) {
            self.onKey = onKey
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }
        override func keyDown(with event: NSEvent) { onKey(event) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            onKey(event)
            return true
        }
    }
}
