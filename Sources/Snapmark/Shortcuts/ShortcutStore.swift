import AppKit
import Carbon
import Observation

// Key codes are physical keys, so shortcuts remain stable when the keyboard layout changes.
struct ShortcutBinding: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.allowedModifiers).rawValue
    }

    static let allowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }
    var isValid: Bool {
        modifiers == modifierFlags.intersection(Self.allowedModifiers).rawValue
            && !modifierFlags.intersection([.command, .option, .control]).isEmpty
    }

    var display: String {
        let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifierFlags.contains($0.0) }.map(\.1).joined() + Self.keyLabel(keyCode)
    }

    private static func keyLabel(_ code: UInt16) -> String {
        let names: [UInt16: String] = [0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V", 11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 18:"1", 19:"2", 20:"3", 21:"4", 22:"6", 23:"5", 24:"=", 25:"9", 26:"7", 27:"−", 28:"8", 29:"0", 30:"]", 31:"O", 32:"U", 33:"[", 34:"I", 35:"P", 37:"L", 38:"J", 39:"'", 40:"K", 41:";", 42:"\\", 43:",", 44:"/", 45:"N", 46:"M", 47:".", 36:"↩", 48:"⇥", 49:"Space", 50:"`", 51:"⌫", 53:"⎋", 123:"←", 124:"→", 125:"↓", 126:"↑", 122:"F1", 120:"F2", 99:"F3", 118:"F4", 96:"F5", 97:"F6", 98:"F7", 100:"F8", 101:"F9", 109:"F10", 103:"F11", 111:"F12"]
        return names[code] ?? "Key \(code)"
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifierFlags.contains(.command) { result |= UInt32(cmdKey) }
        if modifierFlags.contains(.option) { result |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { result |= UInt32(controlKey) }
        if modifierFlags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case captureArea, captureWindow, captureFullScreen, copy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .captureArea: "Capture Area"
        case .captureWindow: "Capture Window"
        case .captureFullScreen: "Capture Full Screen"
        case .copy: "Copy Annotated Image"
        }
    }
    var defaultBinding: ShortcutBinding {
        switch self {
        case .captureArea: ShortcutBinding(keyCode: 0, modifiers: [.control, .option, .command])
        case .captureWindow: ShortcutBinding(keyCode: 13, modifiers: [.control, .option, .command])
        case .captureFullScreen: ShortcutBinding(keyCode: 1, modifiers: [.control, .option, .command])
        case .copy: ShortcutBinding(keyCode: 8, modifiers: [.control, .option, .command])
        }
    }
    var originalDefaultBinding: ShortcutBinding {
        switch self {
        case .captureArea: ShortcutBinding(keyCode: 20, modifiers: [.shift, .command])
        case .captureWindow: ShortcutBinding(keyCode: 21, modifiers: [.shift, .command])
        case .captureFullScreen: ShortcutBinding(keyCode: 19, modifiers: [.shift, .command])
        case .copy: ShortcutBinding(keyCode: 8, modifiers: [.option, .command])
        }
    }
}

@MainActor @Observable final class ShortcutStore {
    private(set) var bindings: [ShortcutAction: ShortcutBinding] = [:]
    private(set) var registrationErrors: [ShortcutAction: String] = [:]
    private(set) var isRecording = false
    var onAction: ((ShortcutAction) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var hotKeys: [ShortcutAction: EventHotKeyRef] = [:]
    @ObservationIgnored private var handler: EventHandlerRef?
    @ObservationIgnored private let registrationEnabled: Bool
    @ObservationIgnored private let registration: ShortcutRegistration
    @ObservationIgnored private var lifecycleObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private static let storageKey = "keyboardShortcuts.v1"
    private static let migrationKey = "keyboardShortcuts.alternateDefaultsMigrated"
    private static let signature: OSType = 0x534E4150

    init(defaults: UserDefaults = .standard, registerHotKeys: Bool = true, registration: ShortcutRegistration = .system,
         applicationNotifications: NotificationCenter = .default,
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.defaults = defaults
        self.registration = registration
        self.registrationEnabled = registerHotKeys
        if let data = defaults.data(forKey: Self.storageKey),
           var saved = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data) {
            if !defaults.bool(forKey: Self.migrationKey) {
                for action in ShortcutAction.allCases where saved[action.rawValue] == action.originalDefaultBinding {
                    if !saved.values.contains(action.defaultBinding) { saved[action.rawValue] = action.defaultBinding }
                }
                if let migrated = try? JSONEncoder().encode(saved) { defaults.set(migrated, forKey: Self.storageKey) }
            }
            for action in ShortcutAction.allCases {
                if let binding = saved[action.rawValue], binding.isValid,
                   !bindings.values.contains(binding) {
                    bindings[action] = binding
                }
            }
        } else {
            for action in ShortcutAction.allCases { bindings[action] = action.defaultBinding }
        }
        defaults.set(true, forKey: Self.migrationKey)
        if registerHotKeys {
            observeLifecycle(applicationNotifications, name: NSApplication.didBecomeActiveNotification)
            observeLifecycle(workspaceNotifications, name: NSWorkspace.didWakeNotification)
            observeLifecycle(workspaceNotifications, name: NSWorkspace.sessionDidBecomeActiveNotification)
            register()
        }
    }

    func binding(for action: ShortcutAction) -> ShortcutBinding? { bindings[action] }
    func display(for action: ShortcutAction) -> String { bindings[action]?.display ?? "None" }

    @discardableResult func set(_ binding: ShortcutBinding?, for action: ShortcutAction) -> String? {
        if let binding {
            guard binding.isValid else { return "Include Command, Option, or Control." }
            if let duplicate = ShortcutAction.allCases.first(where: { $0 != action && bindings[$0] == binding }) {
                return "Already used for \(duplicate.title)."
            }
        }
        if registrationEnabled, action != .copy, let binding,
           binding != bindings[action] || hotKeys[action] == nil {
            let result = register(binding, for: action)
            if let registrationError = result.error {
                let error = registrationError + " The previous shortcut is unchanged."
                registrationErrors[action] = error
                return error
            }
            if let previous = hotKeys.removeValue(forKey: action) { registration.unregister(previous) }
            if let reference = result.reference {
                if isRecording { registration.unregister(reference) }
                else { hotKeys[action] = reference }
            }
        } else if binding == nil, let previous = hotKeys.removeValue(forKey: action) {
            registration.unregister(previous)
        }
        registrationErrors[action] = nil
        bindings[action] = binding
        let saved = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.storageKey) }
        return nil
    }

    func reset(_ action: ShortcutAction) -> String? { set(action.defaultBinding, for: action) }
    func setRecording(_ recording: Bool) {
        guard isRecording != recording else { return }
        isRecording = recording
        register()
    }
    func matches(_ event: NSEvent, action: ShortcutAction) -> Bool {
        guard !isRecording, let binding = bindings[action], event.type == .keyDown else { return false }
        return event.keyCode == binding.keyCode && event.modifierFlags.intersection(ShortcutBinding.allowedModifiers).rawValue == binding.modifiers
    }

    private func observeLifecycle(_ center: NotificationCenter, name: Notification.Name) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.register() }
        }
        lifecycleObservers.append((center, observer))
    }

    private func installHandler() {
        var specification = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x534E4150 else { return OSStatus(eventNotHandledErr) }
            let store = Unmanaged<ShortcutStore>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                let actions = ShortcutAction.allCases
                if !store.isRecording, Int(identifier.id) < actions.count { store.onAction?(actions[Int(identifier.id)]) }
            }
            return noErr
        }, 1, &specification, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr { handler = nil }
    }

    private func register(_ binding: ShortcutBinding, for action: ShortcutAction) -> (reference: EventHotKeyRef?, error: String?) {
        guard handler != nil || !registration.requiresEventHandler else {
            return (nil, "Global keyboard handler is unavailable. Activate Snapmark to retry.")
        }
        let index = ShortcutAction.allCases.firstIndex(of: action)!
        let (reference, status) = registration.register(binding, EventHotKeyID(signature: Self.signature, id: UInt32(index)))
        if status == noErr, let reference { return (reference, nil) }
        return (nil, "\(binding.display) is unavailable (\(status)). macOS or another app may use it. Choose another shortcut.")
    }

    private func register() {
        guard registrationEnabled else { return }
        if isRecording {
            for hotKey in hotKeys.values { registration.unregister(hotKey) }
            hotKeys.removeAll()
            return
        }
        if registration.requiresEventHandler, handler == nil { installHandler() }
        for action in ShortcutAction.allCases where action != .copy {
            guard hotKeys[action] == nil, let binding = bindings[action] else { continue }
            let result = register(binding, for: action)
            hotKeys[action] = result.reference
            registrationErrors[action] = result.error
        }
    }

    deinit {
        for (center, observer) in lifecycleObservers { center.removeObserver(observer) }
        for hotKey in hotKeys.values { registration.unregister(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}


struct ShortcutRegistration {
    var requiresEventHandler = true
    var register: (ShortcutBinding, EventHotKeyID) -> (EventHotKeyRef?, OSStatus)
    var unregister: (EventHotKeyRef) -> Void

    static let system = ShortcutRegistration(register: { binding, identifier in
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(binding.keyCode), binding.carbonModifiers, identifier, GetApplicationEventTarget(), 0, &reference)
        return (reference, status)
    }, unregister: { UnregisterEventHotKey($0) })
}
