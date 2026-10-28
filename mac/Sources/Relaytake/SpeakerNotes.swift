import AppKit
import RelaytakeCore
import SwiftUI

/// A small floating window for what you want to say. It is never in a recording or a screenshot: Hot Take's own
/// windows are left out of every capture, and this one also asks the system not to share it.
@MainActor
final class SpeakerNotesWindow: NSObject, NSWindowDelegate {
    static let shared = SpeakerNotesWindow()
    private var panel: NSPanel?

    var isShowing: Bool { panel?.isVisible == true }

    func toggle() { isShowing ? hide() : show() }

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NotesPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Speaker Notes"
        panel.contentView = NSHostingView(rootView: SpeakerNotesView())
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none  // belt and braces; ScreenCaptureKit also leaves the app's windows out
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 240, height: 140)
        panel.delegate = self
        if !panel.setFrameUsingName("SpeakerNotes") {
            if let frame = NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 24, y: frame.maxY - panel.frame.height - 24))
            }
        }
        panel.setFrameAutosaveName("SpeakerNotes")
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func hide() { panel?.orderOut(nil) }

    func windowWillClose(_ notification: Notification) { panel = nil }
}

/// A panel that can take typing without Hot Take coming to the front over the app being recorded.
private final class NotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct SpeakerNotesView: View {
    @AppStorage(Pref.speakerNotes) private var notes = ""
    @AppStorage(Pref.speakerNotesSize) private var size = 20.0

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $notes)
                .font(.system(size: size))
                .scrollContentBackground(.hidden)
                .padding(8)
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Write what you want to say. This window is not in your recording.")
                            .font(.system(size: size)).foregroundStyle(.tertiary).padding(.horizontal, 13).padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            Divider()
            HStack(spacing: 10) {
                Text(ReadingTime.label(for: notes)).font(.caption).foregroundStyle(.secondary)
                    .help("At a calm speaking pace of about 150 words a minute")
                Spacer()
                Stepper("Text size", value: $size, in: 12...48, step: 2).labelsHidden().help("Text size")
                Image(systemName: "textformat.size").foregroundStyle(.secondary)
                Button("Clear") { notes = "" }.disabled(notes.isEmpty).controlSize(.small)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .frame(minWidth: 240, minHeight: 140)
    }
}
