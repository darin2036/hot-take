import AppKit
import Carbon.HIToolbox
import RelaytakeCore

/// Keys that work from any app. They are registered with the system's hot-key service, which needs no permission
/// and sees only these exact key combinations, never anything else that is typed.
@MainActor
final class GlobalHotkeys {
    static let shared = GlobalHotkeys()

    /// Why a shortcut is not active, by action: refused keys, or keys another app already holds.
    private(set) var problems: [HotkeyAction: String] = [:]
    var onTrigger: ((HotkeyAction) -> Void)?

    private var references: [HotkeyAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x48544B59  // "HTKY"
    private static let actions = HotkeyAction.allCases

    /// The shortcuts the preferences ask for.
    static func stored() -> [HotkeyAction: String] {
        var result: [HotkeyAction: String] = [:]
        for action in HotkeyAction.allCases {
            if let text = UserDefaults.standard.string(forKey: action.preferenceKey) { result[action] = text }
        }
        return result
    }

    /// Registers what the preferences ask for, replacing what was registered before.
    func refresh() {
        unregisterAll()
        problems = [:]
        guard UserDefaults.standard.object(forKey: Pref.hotkeysEnabled) as? Bool ?? true else { return }
        installHandlerIfNeeded()
        let resolved = HotkeyResolver.resolve(stored: Self.stored())
        problems = resolved.refused
        for (action, binding) in resolved.bindings {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(Self.actions.firstIndex(of: action) ?? 0))
            let status = RegisterEventHotKey(UInt32(binding.keyCode), Self.carbon(binding.modifiers), id, GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference {
                references[action] = reference
            } else {
                problems[action] = "\(binding.display) is already in use by another app. Choose different keys."
            }
        }
    }

    private func unregisterAll() {
        for reference in references.values { UnregisterEventHotKey(reference) }
        references = [:]
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == GlobalHotkeys.signature else { return OSStatus(eventNotHandledErr) }
            let index = Int(id.id)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard GlobalHotkeys.actions.indices.contains(index) else { return }
                    GlobalHotkeys.shared.onTrigger?(GlobalHotkeys.actions[index])
                }
            }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    private static func carbon(_ modifiers: HotkeyModifiers) -> UInt32 {
        var flags: Int = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }

    /// The shortcut a key press makes, or nil if it is not one that can be used (so the field can say why not).
    static func binding(for event: NSEvent) -> HotkeyBinding {
        var modifiers: HotkeyModifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return HotkeyBinding(keyCode: event.keyCode, modifiers: modifiers)
    }
}
