import SwiftUI

@main struct SnapmarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var coordinator = AppCoordinator()
    @State private var launchAtLogin = LaunchAtLoginStore()
    var body: some Scene {
        MenuBarExtra("Snapmark", systemImage: "viewfinder") {
            Button("Capture Area   \(coordinator.shortcuts.display(for: .captureArea))") { coordinator.capture(.area) }.disabled(coordinator.isCapturing)
            Button("Capture Window   \(coordinator.shortcuts.display(for: .captureWindow))") { coordinator.capture(.window) }.disabled(coordinator.isCapturing)
            Button("Capture Full Screen   \(coordinator.shortcuts.display(for: .captureFullScreen))") { coordinator.capture(.fullScreen) }.disabled(coordinator.isCapturing)
            Divider()
            Button("Show Last Screenshot") { coordinator.showEditor() }.disabled(coordinator.document == nil)
            Button("Copy Last Screenshot") { coordinator.document?.copy() }.disabled(coordinator.document == nil)
            Divider()
            SettingsLink { Text("Settings…") }.keyboardShortcut(",")
            Button("Quit Snapmark") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        Settings { SettingsView(shortcuts: coordinator.shortcuts, launchAtLogin: launchAtLogin) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
