import AppKit
import AVFoundation
import SwiftUI

/// Shows the Mac's Mic Mode for Hot Take with an "Open Mic Settings" button, in the record sheet and in Settings.
/// While it is on screen the microphone is held open (see `MicrophoneMonitor`), which is what makes the system's
/// Mic Modes menu available. Voice Isolation suits a walkthrough, so anything else gets a nudge. Only the person
/// can change the mode.
struct MicrophoneModeRow: View {
    /// Who is asking for the microphone, so two windows do not close it on each other.
    let owner: String
    let deviceID: String
    /// The record sheet may trigger the system's microphone question; Settings only uses access already given.
    var asksForAccess = false

    @ObservedObject private var monitor = MicrophoneMonitor.shared
    @State private var window: NSWindow?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: shown == .voiceIsolation ? "checkmark.circle.fill" : "waveform.badge.mic")
                .foregroundStyle(shown == .voiceIsolation ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 0) {
                Text("Mic mode: \(shown.title)").font(.callout)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            button
        }
        .background(WindowReader { if window !== $0 { window = $0 } })
        .task(id: deviceID) {
            if asksForAccess { await monitor.requestAccess() }
            monitor.hold(owner, deviceID: deviceID)
        }
        .onDisappear { monitor.release(owner) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if let window, note.object as? NSWindow === window { monitor.release(owner) }
        }
    }

    /// What macOS is applying while the microphone is open here; otherwise the mode chosen in Control Center.
    private var shown: MicrophoneModeStatus { monitor.active ?? monitor.preferred }

    private var detail: String {
        switch monitor.access {
        case .denied, .restricted:
            return "Microphone access is off. Turn it on in System Settings → Privacy & Security → Microphone."
        case .notDetermined:
            return "Hot Take needs microphone access to use Mic Modes."
        default:
            if let active = monitor.active, active != monitor.preferred {
                return "\(monitor.preferred.title) is selected, but macOS is using \(active.title) for this microphone."
            }
            return shown.hint
        }
    }

    @ViewBuilder private var button: some View {
        switch monitor.access {
        case .authorized:
            Button("Open Mic Settings") { Task { await monitor.openSystemMenu(owner: owner, deviceID: deviceID) } }
                .controlSize(.small)
                .help("Opens the system's Mic Modes menu: Standard, Voice Isolation or Wide Spectrum. Your choice is remembered for Hot Take. It can also be changed from Control Center while recording.")
        case .notDetermined:
            Button("Allow…") { Task { await monitor.requestAccess() } }.controlSize(.small)
        default:
            EmptyView()
        }
    }
}
