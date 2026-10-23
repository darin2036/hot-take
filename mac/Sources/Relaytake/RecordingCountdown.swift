import AppKit
import SwiftUI

/// Only visible before capture starts; no countdown frames enter the recording.
@MainActor
final class RecordingCountdown: ObservableObject {
    @Published private(set) var number = 3
    private var canceled = false
    private var panels: [NSPanel] = []

    func run(on screens: [NSScreen]) async -> Bool {
        guard !screens.isEmpty else { return false }
        defer { panels.forEach { $0.orderOut(nil) }; panels = [] }
        for screen in screens {
            let panel = CountdownPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.contentView = NSHostingView(rootView: CountdownView(countdown: self))
            panel.onCancel = { [weak self] in self?.cancel() }
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        NSApp.activate(ignoringOtherApps: true)
        panels.first?.makeKey()
        for value in [3, 2, 1] {
            number = value
            let deadline = ContinuousClock.now.advanced(by: .seconds(1))
            while ContinuousClock.now < deadline {
                if canceled || Task.isCancelled { return false }
                do { try await Task.sleep(for: .milliseconds(40)) } catch { return false }
            }
        }
        return !canceled && !Task.isCancelled
    }

    func cancel() { canceled = true }
}

private final class CountdownPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
}

private struct CountdownView: View {
    @ObservedObject var countdown: RecordingCountdown
    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
            VStack(spacing: 28) {
                Text("\(countdown.number)")
                    .font(.system(size: 220, weight: .bold, design: .rounded))
                    .monospacedDigit().foregroundStyle(.white)
                    .accessibilityLabel("Recording in \(countdown.number)")
                    .accessibilityAddTraits(.updatesFrequently)
                Button("Cancel") { countdown.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
            }
        }.ignoresSafeArea().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
