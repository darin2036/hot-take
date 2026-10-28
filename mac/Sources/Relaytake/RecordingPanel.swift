import AppKit
import RelaytakeCore
import SwiftUI

/// A small always-on-top bar shown only while recording: timer, Restart and Stop.
/// It is excluded from the recording (see ScreenRecorder) and follows you across Spaces. Drag it by its
/// grip (or any empty part of it) out of the way; it comes back there next time.
@MainActor
final class RecordingPanel {
    static let shared = RecordingPanel()
    private var panel: NSPanel?
    private var mover: Any?
    private static let positionKey = "recordingBarOrigin"

    func show(model: RecorderModel) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let host = NSHostingView(rootView: RecordingBar(model: model))
        host.frame.size = host.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: host.frame.size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.sharingType = .none  // belt and braces; ScreenCaptureKit also excludes the app

        if let saved = Self.savedOrigin(for: panel.frame.size) {
            panel.setFrameOrigin(saved)
        } else if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 10))
        }
        // Remember where it was dragged to.
        mover = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { note in
            guard let moved = note.object as? NSWindow else { return }
            UserDefaults.standard.set(NSStringFromPoint(moved.frame.origin), forKey: RecordingPanel.positionKey)
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        if let mover { NotificationCenter.default.removeObserver(mover) }
        mover = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Where the bar was last left, if that spot is still on a connected screen (a display may have been
    /// unplugged since).
    private static func savedOrigin(for size: NSSize) -> NSPoint? {
        guard let text = UserDefaults.standard.string(forKey: positionKey) else { return nil }
        let origin = NSPointFromString(text)
        let frame = NSRect(origin: origin, size: size)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(frame) && $0.visibleFrame.contains(NSPoint(x: frame.midX, y: frame.midY)) }
            ? origin : nil
    }
}

private struct RecordingBar: View {
    @ObservedObject var model: RecorderModel

    var body: some View {
        HStack(spacing: 12) {
            switch model.phase {
            case .recording(let since):
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                    .help("Drag to move this bar out of the way")
                Circle().fill(model.paused ? Color.secondary : Color.red).frame(width: 10, height: 10)
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(timeLabel(model.elapsed(at: context.date)))
                        .font(.system(.body, design: .monospaced).weight(.medium))
                }
                if model.paused {
                    Text("Paused").font(.callout).foregroundStyle(.secondary)
                }
                if model.canPause {
                    Button {
                        model.paused ? model.resume() : model.pause()
                    } label: {
                        Label(model.paused ? "Resume" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.plain)
                    .help(model.paused ? "Carry on with this take" : "Pause. Paused time is left out of the take.")
                }

                Button {
                    model.restart()
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .help("Discard this take and start over")

                Button {
                    model.toggle()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(TakeButtonStyle())
                .help("Stop and save (⌘N)")
            default:
                ProgressView().controlSize(.small)
                Text("Starting…")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .contentShape(Capsule())
        .gesture(WindowDragGesture())  // drag from anywhere that is not a button
        .fixedSize()
    }
}
