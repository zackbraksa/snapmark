import Foundation
import ServiceManagement
import Testing
@testable import Snapmark

struct LaunchAtLoginTests {
    @MainActor @Test func readsSystemStatusWithoutChangingLoginItems() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for status in [SMAppService.Status.enabled, .notRegistered, .requiresApproval, .notFound] {
            let service = TestLoginItemService(status: status)
            let store = LaunchAtLoginStore(defaults: defaults, service: service)
            #expect(store.status == status)
            #expect(store.isEnabled == (status == .enabled))
            #expect(service.registerCount == 0)
            #expect(service.unregisterCount == 0)
        }
    }

    @MainActor @Test func toggleUsesRegistrationAndActualStatus() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = TestLoginItemService(status: .notRegistered)
        let store = LaunchAtLoginStore(defaults: defaults, service: service)
        store.setEnabled(true)
        #expect(service.registerCount == 1)
        #expect(store.isEnabled)
        store.setEnabled(true)
        #expect(service.registerCount == 1)
        store.setEnabled(false)
        #expect(service.unregisterCount == 1)
        #expect(store.status == .notRegistered)
        #expect(!store.isEnabled)
    }

    @MainActor @Test func failedChangesPreserveActualStatusAndReportError() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = TestLoginItemService(status: .notRegistered)
        service.registrationError = TestError.denied
        let store = LaunchAtLoginStore(defaults: defaults, service: service)
        store.setEnabled(true)
        #expect(!store.isEnabled)
        #expect(store.errorMessage != nil)
        service.status = .enabled
        store.refresh()
        #expect(store.errorMessage == nil)
        service.unregistrationError = TestError.denied
        store.setEnabled(false)
        #expect(store.isEnabled)
        #expect(store.errorMessage != nil)
        store.refresh()
        #expect(store.errorMessage != nil)
    }

    @MainActor @Test func pendingApprovalDoesNotClaimEnabledOrReregister() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = TestLoginItemService(status: .notRegistered)
        service.registeredStatus = .requiresApproval
        var openedSettings = false
        let store = LaunchAtLoginStore(defaults: defaults, service: service, openSettings: { openedSettings = true })
        store.setEnabled(true)
        #expect(store.status == .requiresApproval)
        #expect(!store.isEnabled)
        store.setEnabled(true)
        #expect(service.registerCount == 1)
        store.openLoginItemsSettings()
        #expect(openedSettings)
        service.status = .enabled
        store.refresh()
        #expect(store.isEnabled)
        service.status = .requiresApproval
        store.refresh()
        #expect(!store.isEnabled)
    }

    @MainActor @Test func migratesOnlyExplicitSavedEnabledIntent() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: LaunchAtLoginStore.legacyMigrationKey)
        let service = TestLoginItemService(status: .notRegistered)
        let store = LaunchAtLoginStore(defaults: defaults, service: service)
        #expect(store.isEnabled)
        #expect(service.registerCount == 1)
        #expect(!defaults.bool(forKey: LaunchAtLoginStore.legacyMigrationKey))
        store.setEnabled(false)
        _ = LaunchAtLoginStore(defaults: defaults, service: service)
        #expect(service.registerCount == 1)
    }

    @MainActor @Test func migrationRemainsPendingUntilEnabledAndDoesNotRepeatApprovalRequest() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: LaunchAtLoginStore.legacyMigrationKey)
        let service = TestLoginItemService(status: .notRegistered)
        service.registeredStatus = .requiresApproval
        _ = LaunchAtLoginStore(defaults: defaults, service: service)
        #expect(service.registerCount == 1)
        #expect(defaults.bool(forKey: LaunchAtLoginStore.legacyMigrationKey))
        let store = LaunchAtLoginStore(defaults: defaults, service: service)
        #expect(service.registerCount == 1)
        service.status = .enabled
        store.refresh()
        #expect(!defaults.bool(forKey: LaunchAtLoginStore.legacyMigrationKey))
    }

    @MainActor @Test func failedMigrationRetainsIntentUntilUserDisables() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: LaunchAtLoginStore.legacyMigrationKey)
        let service = TestLoginItemService(status: .notRegistered)
        service.registrationError = TestError.denied
        let store = LaunchAtLoginStore(defaults: defaults, service: service)
        #expect(store.errorMessage != nil)
        #expect(defaults.bool(forKey: LaunchAtLoginStore.legacyMigrationKey))
        store.setEnabled(false)
        #expect(!defaults.bool(forKey: LaunchAtLoginStore.legacyMigrationKey))
        _ = LaunchAtLoginStore(defaults: defaults, service: service)
        #expect(service.registerCount == 1)
        #expect(service.unregisterCount == 0)
    }

    @MainActor @Test func successfulCallWithoutEnabledStatusStillReportsFailure() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = TestLoginItemService(status: .notRegistered)
        service.registeredStatus = .notFound
        let store = LaunchAtLoginStore(defaults: defaults, service: service)
        store.setEnabled(true)
        #expect(!store.isEnabled)
        #expect(store.status == .notFound)
        #expect(store.errorMessage != nil)
    }
}

@MainActor
private final class TestLoginItemService: LaunchAtLoginService {
    var status: SMAppService.Status
    var registeredStatus: SMAppService.Status = .enabled
    var registrationError: Error?
    var unregistrationError: Error?
    var registerCount = 0
    var unregisterCount = 0

    init(status: SMAppService.Status) { self.status = status }

    func register() throws {
        registerCount += 1
        if let registrationError { throw registrationError }
        status = registeredStatus
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregistrationError { throw unregistrationError }
        status = .notRegistered
    }
}

private enum TestError: Error { case denied }
