import Foundation

// Global shortcuts: keys that work from any app to start and stop a recording, pause it, or take a
// screenshot. Only the rules live here (what a shortcut is, how it is stored and shown, which ones are
// refused); the app registers the chosen keys with the system, which needs no extra permission.

public struct HotkeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = HotkeyModifiers(rawValue: 1)
    public static let option = HotkeyModifiers(rawValue: 2)
    public static let control = HotkeyModifiers(rawValue: 4)
    public static let shift = HotkeyModifiers(rawValue: 8)
}

/// Why a shortcut cannot be used.
public enum HotkeyProblem: Equatable, Sendable {
    /// Plain keys and Shift alone would fire while typing, in every app.
    case needsModifier
    /// The system or nearly every app already uses it.
    case reserved(String)
    case unknownKey

    public var message: String {
        switch self {
        case .needsModifier: "Hold ⌘, ⌥ or ⌃ as well, so the shortcut does not fire while you type."
        case .reserved(let name): "\(name) is used by the system. Try a different shortcut."
        case .unknownKey: "That key can't be used for a shortcut."
        }
    }
}

public struct HotkeyBinding: Equatable, Hashable, Sendable {
    /// The hardware key (a virtual key code), not the character, so it works with any keyboard layout.
    public var keyCode: UInt16
    public var modifiers: HotkeyModifiers

    public init(keyCode: UInt16, modifiers: HotkeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// What is saved in the preferences: "15:7".
    public var stored: String { "\(keyCode):\(modifiers.rawValue)" }

    public init?(stored text: String) {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let code = UInt16(parts[0]), let raw = Int(parts[1]), raw >= 0, raw < 16 else { return nil }
        let binding = HotkeyBinding(keyCode: code, modifiers: HotkeyModifiers(rawValue: raw))
        guard HotkeyKeys.name(for: code) != nil else { return nil }
        self = binding
    }

    /// "⌃⌥⌘R", in the order the system lists modifiers.
    public var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + (HotkeyKeys.name(for: keyCode) ?? "?")
    }

    public var problem: HotkeyProblem? {
        guard HotkeyKeys.name(for: keyCode) != nil else { return .unknownKey }
        guard !modifiers.isDisjoint(with: [.command, .option, .control]) else { return .needsModifier }
        if let name = Self.reserved[self] { return .reserved(name) }
        return nil
    }

    /// Combinations that belong to the system or to every app. Matching by exact keys and modifiers.
    private static let reserved: [HotkeyBinding: String] = [
        HotkeyBinding(keyCode: 12, modifiers: .command): "⌘Q (Quit)",
        HotkeyBinding(keyCode: 13, modifiers: .command): "⌘W (Close)",
        HotkeyBinding(keyCode: 4, modifiers: .command): "⌘H (Hide)",
        HotkeyBinding(keyCode: 46, modifiers: .command): "⌘M (Minimize)",
        HotkeyBinding(keyCode: 49, modifiers: .command): "⌘Space (Spotlight)",
        HotkeyBinding(keyCode: 48, modifiers: .command): "⌘Tab (App Switcher)",
        HotkeyBinding(keyCode: 53, modifiers: [.command, .option]): "⌥⌘Esc (Force Quit)",
        HotkeyBinding(keyCode: 49, modifiers: [.command, .option]): "⌥⌘Space (Finder search)",
        HotkeyBinding(keyCode: 20, modifiers: [.command, .shift]): "⇧⌘3 (Screenshot)",
        HotkeyBinding(keyCode: 21, modifiers: [.command, .shift]): "⇧⌘4 (Screenshot)",
        HotkeyBinding(keyCode: 23, modifiers: [.command, .shift]): "⇧⌘5 (Screenshot and recording)",
    ]
}

public enum HotkeyAction: String, CaseIterable, Identifiable, Sendable {
    /// Starts a recording of the screen with the last settings, or stops the one in progress.
    case startStop
    case pause
    /// Goes back 10 seconds in the take being recorded and pauses there.
    case rewind
    case screenshot
    /// Like `startStop`, and the take is also turned into a request for a coding agent when it stops.
    case startAgent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .startStop: "Start or stop recording"
        case .pause: "Pause or resume"
        case .rewind: "Rewind 10 seconds while recording"
        case .screenshot: "Take a screenshot"
        case .startAgent: "Start or stop a take for an agent"
        }
    }

    public var preferenceKey: String { "hotkey." + rawValue }

    /// ⌃⌥⌘ plus a letter: nothing else in the system or in common apps uses these.
    public var standard: HotkeyBinding {
        switch self {
        case .startStop: HotkeyBinding(keyCode: 15, modifiers: [.control, .option, .command])  // R
        case .pause: HotkeyBinding(keyCode: 35, modifiers: [.control, .option, .command])  // P
        case .rewind: HotkeyBinding(keyCode: 13, modifiers: [.control, .option, .command])  // W
        case .screenshot: HotkeyBinding(keyCode: 1, modifiers: [.control, .option, .command])  // S
        case .startAgent: HotkeyBinding(keyCode: 0, modifiers: [.control, .option, .command])  // A
        }
    }
}

/// The shortcuts that are on, with no two on the same keys.
public enum HotkeyResolver {
    /// - Parameter stored: each action's saved text; a missing action uses its standard keys, and `""` means off.
    /// - Returns: the bindings to register, and the actions whose keys were refused (with why).
    public static func resolve(stored: [HotkeyAction: String]) -> (bindings: [HotkeyAction: HotkeyBinding], refused: [HotkeyAction: String]) {
        var bindings: [HotkeyAction: HotkeyBinding] = [:]
        var refused: [HotkeyAction: String] = [:]
        var taken: [HotkeyBinding: HotkeyAction] = [:]
        for action in HotkeyAction.allCases {
            let binding: HotkeyBinding
            switch stored[action] {
            case nil: binding = action.standard
            case let text? where text.isEmpty: continue
            case let text?:
                guard let parsed = HotkeyBinding(stored: text) else { refused[action] = HotkeyProblem.unknownKey.message; continue }
                binding = parsed
            }
            if let problem = binding.problem { refused[action] = problem.message; continue }
            if let other = taken[binding] {
                refused[action] = "\(binding.display) is already used for “\(other.title)”."
                continue
            }
            taken[binding] = action
            bindings[action] = binding
        }
        return (bindings, refused)
    }
}

public enum HotkeyKeys {
    /// The label of a key on a US keyboard, or nil for a key that cannot be a shortcut.
    public static func name(for keyCode: UInt16) -> String? { names[keyCode] }

    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 49: "Space", 50: "`",
        48: "Tab", 53: "Esc", 36: "↩", 51: "⌫",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

/// Which screen a quick recording or screenshot uses when no one is choosing.
public enum QuickCapturePlan {
    /// The display used last time if it is still connected, else the main one, else the first.
    public static func display(last: UInt32?, connected: [UInt32], main: UInt32?) -> UInt32? {
        if let last, connected.contains(last) { return last }
        if let main, connected.contains(main) { return main }
        return connected.first
    }
}
