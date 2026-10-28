import AppKit
import RelaytakeCore
import SwiftUI

/// Settings → Recording: global shortcuts, hiding notifications, and the speaker notes window.
struct ShortcutsSection: View {
    @AppStorage(Pref.hotkeysEnabled) private var enabled = true
    @AppStorage(Pref.hideNotifications) private var hideNotifications = true

    var body: some View {
        Section {
            Toggle("Use shortcuts that work in any app", isOn: $enabled)
                .help("Start, pause and stop a recording, or take a screenshot, from any app. Hot Take sees only these exact keys.")
                .onChange(of: enabled) { _, _ in GlobalHotkeys.shared.refresh() }
            if enabled {
                ForEach(HotkeyAction.allCases) { HotkeyRow(action: $0) }
            }
            Toggle("Hide notifications in recordings", isOn: $hideNotifications)
                .help("Leaves Notification Center out of screen and area recordings and screenshots, so a banner that pops up is not in the video. It does not turn on Do Not Disturb.")
            LabeledContent("Speaker notes") {
                Button("Show Notes") { SpeakerNotesWindow.shared.show() }
                    .help("A floating window for what you want to say. It is never in a recording.")
            }
        } header: {
            Text("Shortcuts and notes")
        }
    }
}

private struct HotkeyRow: View {
    let action: HotkeyAction
    @AppStorage private var stored: String
    @State private var listening = false
    @State private var monitor: Any?
    @State private var note = ""

    init(action: HotkeyAction) {
        self.action = action
        _stored = AppStorage(wrappedValue: action.standard.stored, action.preferenceKey)
    }

    private var shown: String { stored.isEmpty ? "Off" : (HotkeyBinding(stored: stored)?.display ?? "Off") }
    private var problem: String? { note.isEmpty ? GlobalHotkeys.shared.problems[action] : note }

    var body: some View {
        LabeledContent(action.title) {
            HStack(spacing: 6) {
                Button(listening ? "Press the keys…" : shown) { listening ? stopListening() : startListening() }
                    .frame(minWidth: 96)
                    .help("Click, then press the keys you want. Hold ⌘, ⌥ or ⌃ with a key. Esc cancels.")
                Button("Reset") { stored = action.standard.stored; apply() }
                    .disabled(stored == action.standard.stored).controlSize(.small)
                Button("Off") { stored = ""; apply() }.disabled(stored.isEmpty).controlSize(.small)
            }
        }
        if let problem {
            Text(problem).font(.caption).foregroundStyle(.orange)
        }
    }

    private func apply() {
        note = ""
        GlobalHotkeys.shared.refresh()
    }

    private func startListening() {
        listening = true
        note = ""
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopListening(); return nil }  // Esc
            let binding = GlobalHotkeys.binding(for: event)
            if let problem = binding.problem {
                note = problem.message
                return nil
            }
            stored = binding.stored
            stopListening()
            apply()
            return nil
        }
    }

    private func stopListening() {
        listening = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
