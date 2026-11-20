import AppKit
import Carbon
import Testing
@testable import Snapmark

struct ShortcutTests {
    @MainActor @Test func shortcutsPersistIncludingClearedBindings() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShortcutStore(defaults: defaults, registerHotKeys: false)
        #expect(store.binding(for: .captureArea) == ShortcutAction.captureArea.defaultBinding)
        let custom = ShortcutBinding(keyCode: 0, modifiers: [.command, .option])
        #expect(store.set(custom, for: .captureArea) == nil)
        #expect(store.set(nil, for: .captureWindow) == nil)
        let restored = ShortcutStore(defaults: defaults, registerHotKeys: false)
        #expect(restored.binding(for: .captureArea) == custom)
        #expect(restored.binding(for: .captureWindow) == nil)
        #expect(restored.binding(for: .copy) == ShortcutAction.copy.defaultBinding)
    }

    @MainActor @Test func rejectsDuplicatesAndUnmodifiedKeys() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShortcutStore(defaults: defaults, registerHotKeys: false)
        #expect(store.set(ShortcutAction.copy.defaultBinding, for: .captureArea) != nil)
        #expect(store.set(ShortcutBinding(keyCode: 0, modifiers: .shift), for: .captureArea) != nil)
        #expect(store.binding(for: .captureArea) == ShortcutAction.captureArea.defaultBinding)
    }

    @MainActor @Test func matchesCopyAndSuspendsDuringRecording() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShortcutStore(defaults: defaults, registerHotKeys: false)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option, .control, .capsLock], timestamp: 0, windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
        #expect(store.matches(event, action: .copy))
        store.setRecording(true)
        #expect(!store.matches(event, action: .copy))
        store.setRecording(false)
        #expect(store.matches(event, action: .copy))
    }

    @MainActor @Test func failedRegistrationPreservesPreviousShortcut() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let previous = ShortcutBinding(keyCode: 109, modifiers: [.command, .control, .option, .shift])
        let occupied = ShortcutBinding(keyCode: 111, modifiers: [.command, .control, .option, .shift])
        defaults.set(try JSONEncoder().encode([ShortcutAction.captureArea.rawValue: previous]), forKey: "keyboardShortcuts.v1")
        let reference = try #require(EventHotKeyRef(bitPattern: 1))
        var registered: ShortcutBinding?
        var unregisterCount = 0
        let registration = ShortcutRegistration(requiresEventHandler: false, register: { binding, _ in
            if binding == occupied { return (nil, OSStatus(eventHotKeyExistsErr)) }
            registered = binding
            return (reference, noErr)
        }, unregister: { _ in
            unregisterCount += 1
            registered = nil
        })
        let store = ShortcutStore(defaults: defaults, registration: registration)
        #expect(store.registrationErrors[.captureArea] == nil)
        #expect(registered == previous)
        #expect(store.set(occupied, for: .captureArea) != nil)
        #expect(store.binding(for: .captureArea) == previous)
        #expect(store.registrationErrors[.captureArea] != nil)
        #expect(registered == previous)
        #expect(unregisterCount == 0)
        let restored = ShortcutStore(defaults: defaults, registerHotKeys: false)
        #expect(restored.binding(for: .captureArea) == previous)
    }

    @MainActor @Test func ignoresInvalidSavedModifiers() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"captureArea":{"keyCode":20,"modifiers":0},"captureWindow":{"keyCode":21,"modifiers":1114112}}"#.utf8), forKey: "keyboardShortcuts.v1")
        let store = ShortcutStore(defaults: defaults, registerHotKeys: false)
        #expect(store.binding(for: .captureArea) == nil)
        #expect(store.binding(for: .captureWindow) == nil)
    }

    @MainActor @Test func migratesOriginalDefaultsOnce() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0.rawValue, $0.originalDefaultBinding) })
        defaults.set(try JSONEncoder().encode(original), forKey: "keyboardShortcuts.v1")
        let store = ShortcutStore(defaults: defaults, registerHotKeys: false)
        for action in ShortcutAction.allCases { #expect(store.binding(for: action) == action.defaultBinding) }
        #expect(store.set(ShortcutAction.captureArea.originalDefaultBinding, for: .captureArea) == nil)
        let restored = ShortcutStore(defaults: defaults, registerHotKeys: false)
        #expect(restored.binding(for: .captureArea) == ShortcutAction.captureArea.originalDefaultBinding)
    }

    @MainActor @Test func migrationPreservesCustomClearedAndOccupiedBindings() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let custom = ShortcutAction.captureArea.defaultBinding
        let saved = [ShortcutAction.captureArea.rawValue: ShortcutAction.captureArea.originalDefaultBinding,
                     ShortcutAction.captureWindow.rawValue: custom,
                     ShortcutAction.copy.rawValue: ShortcutAction.copy.originalDefaultBinding]
        defaults.set(try JSONEncoder().encode(saved), forKey: "keyboardShortcuts.v1")
        let store = ShortcutStore(defaults: defaults, registerHotKeys: false)
        #expect(store.binding(for: .captureArea) == ShortcutAction.captureArea.originalDefaultBinding)
        #expect(store.binding(for: .captureWindow) == custom)
        #expect(store.binding(for: .captureFullScreen) == nil)
        #expect(store.binding(for: .copy) == ShortcutAction.copy.defaultBinding)
    }

    @MainActor @Test func retriesLaunchConflictsOnActivationWakeAndSessionActivation() throws {
        for notification in [NSApplication.didBecomeActiveNotification, NSWorkspace.didWakeNotification,
                             NSWorkspace.sessionDidBecomeActiveNotification] {
            let suite = "SnapmarkTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let applicationNotifications = NotificationCenter()
            let workspaceNotifications = NotificationCenter()
            let reference = try #require(EventHotKeyRef(bitPattern: 1))
            var isOccupied = true
            var attempts: [ShortcutBinding] = []
            var unregisterCount = 0
            let registration = ShortcutRegistration(requiresEventHandler: false, register: { binding, _ in
                attempts.append(binding)
                if binding == ShortcutAction.captureArea.defaultBinding, isOccupied {
                    return (nil, OSStatus(eventHotKeyExistsErr))
                }
                return (reference, noErr)
            }, unregister: { _ in unregisterCount += 1 })
            let store = ShortcutStore(defaults: defaults, registration: registration,
                                      applicationNotifications: applicationNotifications,
                                      workspaceNotifications: workspaceNotifications)
            #expect(attempts.count == 3)
            #expect(store.registrationErrors[.captureArea] != nil)
            #expect(store.registrationErrors[.captureWindow] == nil)
            #expect(store.binding(for: .captureArea) == ShortcutAction.captureArea.defaultBinding)
            isOccupied = false
            let center = notification == NSApplication.didBecomeActiveNotification ? applicationNotifications : workspaceNotifications
            center.post(name: notification, object: nil)
            #expect(attempts.count == 4)
            #expect(attempts.last == ShortcutAction.captureArea.defaultBinding)
            #expect(store.registrationErrors[.captureArea] == nil)
            #expect(unregisterCount == 0)
            center.post(name: notification, object: nil)
            #expect(attempts.count == 4)
        }
    }

    @MainActor @Test func lifecycleRetriesRespectRecordingAndReleaseObservers() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let applicationNotifications = NotificationCenter()
        let workspaceNotifications = NotificationCenter()
        let reference = try #require(EventHotKeyRef(bitPattern: 1))
        var registerCount = 0
        var unregisterCount = 0
        let registration = ShortcutRegistration(requiresEventHandler: false, register: { _, _ in
            registerCount += 1
            return (reference, noErr)
        }, unregister: { _ in unregisterCount += 1 })
        var store: ShortcutStore? = ShortcutStore(defaults: defaults, registration: registration,
                                                 applicationNotifications: applicationNotifications,
                                                 workspaceNotifications: workspaceNotifications)
        let isReleased = { [weak store] in store == nil }
        #expect(registerCount == 3)
        store?.setRecording(true)
        #expect(unregisterCount == 3)
        applicationNotifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        workspaceNotifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        workspaceNotifications.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        #expect(registerCount == 3)
        store?.setRecording(false)
        #expect(registerCount == 6)
        store = nil
        #expect(isReleased())
        #expect(unregisterCount == 6)
        applicationNotifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        workspaceNotifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(registerCount == 6)
    }

    @MainActor @Test func launchConflictPreservesSavedBindingAndClearedActions() throws {
        let suite = "SnapmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let custom = ShortcutBinding(keyCode: 109, modifiers: [.command, .control])
        let saved = try JSONEncoder().encode([ShortcutAction.captureArea.rawValue: custom])
        defaults.set(saved, forKey: "keyboardShortcuts.v1")
        var attempts: [ShortcutBinding] = []
        let registration = ShortcutRegistration(requiresEventHandler: false, register: { binding, _ in
            attempts.append(binding)
            return (nil, OSStatus(eventHotKeyExistsErr))
        }, unregister: { _ in Issue.record("A failed registration has no hotkey to unregister.") })
        let store = ShortcutStore(defaults: defaults, registration: registration,
                                  applicationNotifications: NotificationCenter(), workspaceNotifications: NotificationCenter())
        #expect(attempts == [custom])
        #expect(store.binding(for: .captureArea) == custom)
        #expect(store.binding(for: .captureWindow) == nil)
        #expect(store.registrationErrors[.captureArea] != nil)
        #expect(store.registrationErrors[.captureArea]?.contains("previous shortcut is unchanged") == false)
        let restored = ShortcutStore(defaults: defaults, registerHotKeys: false)
        #expect(restored.binding(for: .captureArea) == custom)
        #expect(restored.binding(for: .captureWindow) == nil)
    }

}
