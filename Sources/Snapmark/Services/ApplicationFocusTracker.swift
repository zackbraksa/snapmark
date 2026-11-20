import AppKit

typealias FocusRestoration = @MainActor () -> Void

@MainActor final class ApplicationFocusTracker {
    private let workspace: NSWorkspace
    private var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        remember(workspace.frontmostApplication)
        activationObserver = workspace.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.remember(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            }
        }
    }

    func restorationForCapture() -> FocusRestoration? {
        remember(workspace.frontmostApplication)
        guard let application = lastExternalApplication, !application.isTerminated else { return nil }
        return {
            guard !application.isTerminated else { return }
            application.activate(options: [])
        }
    }

    private func remember(_ application: NSRunningApplication?) {
        guard let application, application.processIdentifier != ProcessInfo.processInfo.processIdentifier, !application.isTerminated else { return }
        lastExternalApplication = application
    }

    deinit {
        if let activationObserver { workspace.notificationCenter.removeObserver(activationObserver) }
    }
}
