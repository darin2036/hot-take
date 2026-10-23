import AppKit
import RelaytakeCore
import ScreenCaptureKit

/// Wraps the system's own content picker so the user chooses a window or app in system UI.
/// The picker returns a ready-made filter; Hot Take never enumerates other apps' windows itself.
@MainActor
final class ContentPicker: NSObject, SCContentSharingPickerObserver {
    private var continuation: CheckedContinuation<SCContentFilter?, Never>?

    func pick() async -> SCContentFilter? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let picker = SCContentSharingPicker.shared
            var configuration = SCContentSharingPickerConfiguration()
            configuration.allowedPickerModes = [.singleWindow, .singleApplication]
            configuration.allowsChangingSelectedContent = false
            picker.defaultConfiguration = configuration
            picker.add(self)
            picker.isActive = true
            picker.present()
        }
    }

    private func finish(_ filter: SCContentFilter?) {
        guard let continuation else { return }
        self.continuation = nil
        SCContentSharingPicker.shared.isActive = false
        SCContentSharingPicker.shared.remove(self)
        continuation.resume(returning: filter)
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in self.finish(filter) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

struct RegionSelection {
    let displayID: CGDirectDisplayID
    /// Points, relative to the display's top-left corner (what ScreenCaptureKit expects).
    let rect: CGRect
}

/// Dims every display and lets the user drag out a rectangle. Esc cancels.
@MainActor
final class RegionSelector {
    private var panels: [NSPanel] = []
    private var continuation: CheckedContinuation<RegionSelection?, Never>?

    func select() async -> RegionSelection? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            NSApplication.shared.activate(ignoringOtherApps: true)
            for screen in NSScreen.screens {
                let panel = SelectionPanel(
                    contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                panel.level = .popUpMenu
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.isReleasedWhenClosed = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
                view.onFinish = { [weak self] rect in
                    guard let self else { return }
                    guard let rect, let id = screen.displayID else { self.finish(nil); return }
                    let flipped = CaptureGeometry.topLeftRect(fromBottomLeft: rect, displayHeight: screen.frame.height)
                    self.finish(RegionSelection(displayID: id, rect: flipped))
                }
                panel.contentView = view
                panel.setFrame(screen.frame, display: true)
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(view)
                panels.append(panel)
            }
        }
    }

    private func finish(_ selection: RegionSelection?) {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        guard let continuation else { return }
        self.continuation = nil
        // Let the dimming overlay leave the screen before capture begins.
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            continuation.resume(returning: selection)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var anchor: NSPoint?
    private var selection: NSRect?

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        guard let selection else {
            drawHint("Drag to select an area to record  ·  Esc to cancel")
            return
        }
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 2
        border.stroke()
        drawLabel("\\(Int(selection.width)) × \\(Int(selection.height))", near: selection)
    }

    private func drawHint(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    private func drawLabel(_ text: String, near rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let box = NSRect(x: rect.minX, y: max(2, rect.minY - size.height - 8), width: size.width + 12, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        text.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 2), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = NSRect(
            x: min(anchor.x, point.x), y: min(anchor.y, point.y),
            width: abs(point.x - anchor.x), height: abs(point.y - anchor.y)
        ).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { anchor = nil }
        guard let selection, selection.width >= 40, selection.height >= 40 else {
            self.selection = nil
            needsDisplay = true
            return
        }
        onFinish?(selection)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }
    }
}
