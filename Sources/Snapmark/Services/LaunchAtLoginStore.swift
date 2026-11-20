import Foundation
import Observation
import OSLog
import ServiceManagement

@MainActor
protocol LaunchAtLoginService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

private struct MainAppLaunchAtLoginService: LaunchAtLoginService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor
@Observable
final class LaunchAtLoginStore {
    static let legacyMigrationKey = "launchAtLogin.migrateEnabledLegacyItem"

    private(set) var status: SMAppService.Status
    private(set) var errorMessage: String?
    private let service: any LaunchAtLoginService
    private let defaults: UserDefaults
    private let openSettings: () -> Void
    private let logger = Logger(subsystem: "xyz.braksa.snapmark", category: "LaunchAtLogin")

    var isEnabled: Bool { status == .enabled }

    init(defaults: UserDefaults = .standard, service: (any LaunchAtLoginService)? = nil,
         openSettings: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() }) {
        let service = service ?? MainAppLaunchAtLoginService()
        self.defaults = defaults
        self.service = service
        self.openSettings = openSettings
        status = service.status
        logStatus()
        if defaults.bool(forKey: Self.legacyMigrationKey) {
            if status == .enabled {
                defaults.removeObject(forKey: Self.legacyMigrationKey)
            } else if status != .requiresApproval {
                setEnabled(true)
            }
        }
    }

    func refresh() {
        let previousStatus = status
        status = service.status
        if status != previousStatus {
            errorMessage = nil
        }
        if status == .enabled {
            defaults.removeObject(forKey: Self.legacyMigrationKey)
        }
        logStatus()
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        status = service.status
        if !enabled {
            defaults.removeObject(forKey: Self.legacyMigrationKey)
        }
        do {
            if enabled {
                if status != .enabled && status != .requiresApproval {
                    try service.register()
                }
            } else if status != .notRegistered {
                try service.unregister()
            }
        } catch {
            errorMessage = "Could not \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
            let error = error as NSError
            logger.error("Login item change failed: \(error.domain, privacy: .public) (\(error.code))")
        }
        status = service.status
        if status == .enabled {
            defaults.removeObject(forKey: Self.legacyMigrationKey)
        }
        if enabled && status != .enabled && status != .requiresApproval && errorMessage == nil {
            errorMessage = "macOS did not enable launch at login. Try again from the installed app in Applications."
        }
        logStatus()
    }

    func openLoginItemsSettings() {
        openSettings()
    }

    private func logStatus() {
        logger.info("Login item status: \(self.status.rawValue); migration pending: \(self.defaults.bool(forKey: Self.legacyMigrationKey))")
    }
}
