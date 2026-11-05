import CoreGraphics
import Foundation
import RelaytakeCore

// Real mouse and keyboard events, so an agent can drive the app it is demoing, and so the pointer moves on screen and Hot Take notes
// each click for zooms and click rings. They are posted from this `hottake` process, which the agent runs, so they carry the agent's
// own permissions; Hot Take itself is not given any. They happen only if the person has turned on both Settings ▸ Recording ▸
// "Let local agents control recording" and "Also let agents use the mouse and keyboard", which the app confirms before each action.

enum InputAction {
    case move(x: Double, y: Double, display: Int?)
    case click(x: Double, y: Double, display: Int?, double: Bool)
    case drag(x1: Double, y1: Double, x2: Double, y2: Double, display: Int?)
    case key(String)
    case type(String)
}

enum InputError: Error { case refused(String) }

/// Asks the app whether input is allowed, then does it. Anything it cannot do comes back as a failure, never a crash.
func performInput(_ action: InputAction, send: (AgentRequest) throws -> AgentResponse) -> AgentResponse {
    do {
        let ping = try send(AgentRequest(command: "ping"))
        guard ping.ok else { return .failure(ping.error ?? "Hot Take did not answer.") }
        guard ping.inputAllowed == true else {
            return .failure("Hot Take has not been told to let agents use the mouse and keyboard. Turn on Settings > Recording > \"Also let agents use the mouse and keyboard\" first.")
        }
        return try run(action, send: send)
    } catch InputError.refused(let message) {
        return .failure(message)
    } catch ClientError.unreachable(let message) {
        return .failure(message)
    } catch {
        return .failure("\(error)")
    }
}

private func run(_ action: InputAction, send: (AgentRequest) throws -> AgentResponse) throws -> AgentResponse {
    func point(_ x: Double, _ y: Double, _ display: Int?) throws -> CGPoint {
        guard let display else {
            guard x.isFinite, y.isFinite else { throw InputError.refused("That is not a position.") }
            return CGPoint(x: x, y: y)
        }
        let list = try send(AgentRequest(command: "displays")).displays ?? []
        guard let found = list.first(where: { $0.number == display }) else {
            throw InputError.refused("There is no display \(display). This Mac has \(list.count).")
        }
        guard let desktop = found.desktopPoint(x: x, y: y) else {
            throw InputError.refused("(\(Int(x)), \(Int(y))) is outside display \(display), which is \(Int(found.width)) by \(Int(found.height)) points.")
        }
        return CGPoint(x: desktop.x, y: desktop.y)
    }

    switch action {
    case .move(let x, let y, let display):
        let target = try point(x, y, display)
        Pointer.glide(to: target)
        return AgentResponse(applied: ["Moved the pointer to (\(Int(target.x)), \(Int(target.y)))."])
    case .click(let x, let y, let display, let double):
        let target = try point(x, y, display)
        Pointer.glide(to: target)
        usleep(150_000)
        Pointer.click(at: target, count: double ? 2 : 1)
        return AgentResponse(applied: ["\(double ? "Double-clicked" : "Clicked") at (\(Int(target.x)), \(Int(target.y)))."])
    case .drag(let x1, let y1, let x2, let y2, let display):
        let from = try point(x1, y1, display), to = try point(x2, y2, display)
        Pointer.drag(from: from, to: to)
        return AgentResponse(applied: ["Dragged from (\(Int(from.x)), \(Int(from.y))) to (\(Int(to.x)), \(Int(to.y)))."])
    case .key(let spec):
        let keys = try Keyboard.parse(spec)
        Keyboard.press(keys)
        return AgentResponse(applied: ["Pressed \(spec)."])
    case .type(let text):
        guard text.count <= 2000 else { throw InputError.refused("That is too much text to type at once (the limit is 2000 characters).") }
        Keyboard.type(text)
        return AgentResponse(applied: ["Typed \(text.count) character\(text.count == 1 ? "" : "s")."])
    }
}

private enum Pointer {
    static func post(_ type: CGEventType, _ point: CGPoint, clickState: Int64 = 1) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: clickState)
        event.post(tap: .cghidEventTap)
    }

    /// Moves the pointer there in a short smooth glide, so a viewer can follow it.
    static func glide(to target: CGPoint) {
        let start = CGEvent(source: nil)?.location ?? target
        let steps = 25
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            post(.mouseMoved, CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t))
            usleep(12_000)
        }
    }

    static func click(at point: CGPoint, count: Int) {
        for number in 1...max(1, count) {
            post(.leftMouseDown, point, clickState: Int64(number))
            usleep(50_000)
            post(.leftMouseUp, point, clickState: Int64(number))
            if number < count { usleep(70_000) }
        }
    }

    static func drag(from start: CGPoint, to end: CGPoint) {
        glide(to: start)
        usleep(100_000)
        post(.leftMouseDown, start)
        usleep(100_000)
        let steps = 25
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            usleep(12_000)
        }
        post(.leftMouseUp, end)
    }
}

enum Keyboard {
    struct Chord: Equatable {
        var code: CGKeyCode
        var flags: CGEventFlags
    }

    /// US-layout key codes for the keys a demo uses.
    static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41,
        "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53, "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand, "shift": .maskShift, "opt": .maskAlternate, "option": .maskAlternate,
        "alt": .maskAlternate, "ctrl": .maskControl, "control": .maskControl,
    ]

    /// "cmd+shift+s" or "return" or "escape".
    static func parse(_ spec: String) throws -> Chord {
        let parts = spec.lowercased().split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, !last.isEmpty else { throw InputError.refused("“\(spec)” is not a key. Try return, escape, tab, space, the arrows, a letter, or a combination like cmd+shift+s.") }
        guard let code = codes[last] else { throw InputError.refused("“\(last)” is not a key hottake knows. Try return, escape, tab, space, delete, the arrows, a letter or digit.") }
        var flags: CGEventFlags = []
        for name in parts.dropLast() {
            guard let flag = modifiers[name] else { throw InputError.refused("“\(name)” is not a modifier. Use cmd, shift, opt or ctrl.") }
            flags.insert(flag)
        }
        return Chord(code: code, flags: flags)
    }

    static func press(_ chord: Chord) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: chord.code, keyDown: down) else { continue }
            event.flags = chord.flags
            event.post(tap: .cghidEventTap)
            usleep(20_000)
        }
    }

    /// Types text as it is, whatever the keyboard layout, a few characters at a time.
    static func type(_ text: String) {
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let chunk = Array(units[index..<min(units.count, index + 16)])
            index += chunk.count
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.post(tap: .cghidEventTap)
            }
            usleep(15_000)
        }
    }
}
