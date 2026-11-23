import AppKit
import SwiftUI
import Observation

@MainActor @Observable final class AppCoordinator {
    let shortcuts: ShortcutStore
    private let captureService = CaptureService()
    private let focusTracker = ApplicationFocusTracker()
    private var restoreSourceFocus: FocusRestoration?
    var document: EditorDocument?
    var isCapturing = false
    private var editorWindow: NSWindow?
    private var eventMonitor: Any?
    init(shortcuts: ShortcutStore? = nil) {
        self.shortcuts = shortcuts ?? ShortcutStore()
        self.shortcuts.onAction = { [weak self] action in
            switch action {
            case .captureArea: self?.capture(.area)
            case .captureWindow: self?.capture(.window)
            case .captureFullScreen: self?.capture(.fullScreen)
            case .copy: self?.copyAndCloseEditor()
            }
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let document = self.document, self.editorWindow?.isKeyWindow == true else { return event }
            let flags = event.modifierFlags.intersection(ShortcutBinding.allowedModifiers)
            if let textView = self.editorWindow?.firstResponder as? NSTextView, textView.isEditable,
               flags == .command || flags == [.command, .shift],
               ["z", "c", "x", "v", "a"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "") { return event }
            if self.shortcuts.matches(event, action: .copy) { self.copyAndCloseEditor(); return nil }
            if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "z" { document.undo(); return nil }
            if flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "z" { document.redo(); return nil }
            return event
        }
    }
    func capture(_ mode: CaptureMode) {
        guard !isCapturing else { return }
        isCapturing = true
        let restorePreviousFocus = focusTracker.restorationForCapture()
        let wasVisible = editorWindow?.isVisible == true
        editorWindow?.orderOut(nil)
        Task {
            do {
                // Let the menu dismiss before taking the image.
                try await Task.sleep(for: .milliseconds(180))
                if let image = try await captureService.capture(mode) {
                    presentScreenshot(EditorDocument(image: image), restoringFocus: restorePreviousFocus)
                } else {
                    if wasVisible { editorWindow?.orderFront(nil) }
                    restorePreviousFocus?()
                }
            } catch {
                if wasVisible { showEditor() }
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert(); alert.messageText = "Screenshot unavailable"; alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Screen Recording Settings")
                if alert.runModal() == .alertSecondButtonReturn, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
            }
            isCapturing = false
        }
    }
    func presentScreenshot(_ document: EditorDocument, restoringFocus: FocusRestoration?) {
        self.document = document
        restoreSourceFocus = restoringFocus
        document.automaticCopy()
        showEditor()
    }
    func copyAndCloseEditor() {
        guard document?.copy() == true else { return }
        editorWindow?.close()
        restoreSourceFocus?()
    }
    func showEditor() {
        guard let document else { return }
        let window: NSWindow
        if let editorWindow { window = editorWindow }
        else {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.contentMinSize = EditorView.minimumContentSize
            window.isReleasedWhenClosed = false; window.title = "Snapmark"; window.center(); editorWindow = window
        }
        window.contentView = NSHostingView(rootView: EditorView(document: document, onCopy: { [weak self] in
            self?.copyAndCloseEditor()
        }))
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}
