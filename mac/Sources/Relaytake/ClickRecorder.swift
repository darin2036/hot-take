import AppKit
import CoreGraphics
import RelaytakeCore
import ScreenCaptureKit

/// Notes where and when the mouse is clicked while a recording runs, as a fraction of the recorded
/// picture, so the Studio can propose zooms. Only the position and time of each click are kept: never
/// which app was clicked, what was typed, or anything else, and nothing leaves this Mac.
@MainActor
final class ClickRecorder {
    private var monitors: [Any] = []
    private var startedAt = Date()
    private var locate: ((CGPoint) -> CGPoint?)?
    private(set) var clicks: [ClickEvent] = []

    /// "screen", "window" or "area": stored with the take.
    static func kind(of target: RecordingTarget) -> String {
        switch target {
        case .display: "screen"
        case .window: "window"
        case .region: "area"
        }
    }

    func start(target: RecordingTarget, startedAt: Date) {
        stop()
        clicks = []
        listen(target: target, startedAt: startedAt)
    }

    /// Carries on after a pause, keeping the clicks so far. `startedAt` is moved forward by the paused time.
    func resume(target: RecordingTarget, startedAt: Date) {
        stop()
        listen(target: target, startedAt: startedAt)
    }

    private func listen(target: RecordingTarget, startedAt: Date) {
        self.startedAt = startedAt
        locate = Self.locator(for: target)
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        // Clicks in other apps arrive through the global monitor, clicks in this app through the local one.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor in self?.note(point) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let point = NSEvent.mouseLocation
            Task { @MainActor in self?.note(point) }
            return event
        }) { monitors.append(local) }
    }

    /// Forgets clicks after `time` seconds, for footage that was rewound over.
    func drop(after time: Double) {
        clicks.removeAll { $0.time > time }
    }

    /// Stops listening and returns the clicks, oldest first.
    @discardableResult
    func stop() -> [ClickEvent] {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        locate = nil
        return clicks
    }

    private func note(_ screenPoint: CGPoint) {
        guard let locate, let spot = locate(screenPoint) else { return }
        clicks.append(ClickEvent(time: max(0, Date().timeIntervalSince(startedAt)), x: spot.x, y: spot.y))
    }

    /// Turns a mouse position (screen coordinates, from the bottom-left) into a 0...1 position in
    /// the recorded picture, or nil when the click was outside it.
    private static func locator(for target: RecordingTarget) -> (CGPoint) -> CGPoint? {
        func fraction(_ point: CGPoint, in rect: CGRect) -> CGPoint? {
            guard rect.width > 0, rect.height > 0, rect.contains(point) else { return nil }
            return CGPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
        }
        switch target {
        case .display(let id):
            return { point in
                guard let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { return nil }
                let local = CGPoint(x: point.x, y: screen.frame.maxY - point.y)  // top-left origin
                return fraction(local, in: CGRect(x: screen.frame.minX, y: 0, width: screen.frame.width, height: screen.frame.height))
            }
        case .region(let id, let rect):
            return { point in
                guard let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { return nil }
                let local = CGPoint(x: point.x - screen.frame.minX, y: screen.frame.maxY - point.y)
                return fraction(local, in: rect)
            }
        case .window(let filter):
            guard let windowID = filter.includedWindows.first?.windowID else { return { _ in nil } }
            return { point in
                // Windows move, so ask where this one is at the moment of the click. Those bounds are
                // measured from the top-left of the main display.
                guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
                      let bounds = info.first?[kCGWindowBounds as String] as? [String: CGFloat],
                      let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], let height = bounds["Height"],
                      let main = NSScreen.screens.first
                else { return nil }
                let global = CGPoint(x: point.x, y: main.frame.height - point.y)
                return fraction(global, in: CGRect(x: x, y: y, width: width, height: height))
            }
        }
    }
}
