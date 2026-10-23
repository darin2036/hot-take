import AVFoundation
import AppKit
import RelaytakeCore
import ScreenCaptureKit
import SwiftUI

/// How big the presenter circle is, as a fraction of the picture's height. Chosen in the record sheet.
enum PresenterSize: String, CaseIterable, Identifiable {
    case small, large

    var id: String { rawValue }
    var title: String { self == .small ? "Small" : "Large" }
    var fraction: Double { self == .small ? 0.15 : 0.24 }
    static var current: PresenterSize {
        PresenterSize(rawValue: UserDefaults.standard.string(forKey: Pref.presenterSize) ?? "") ?? .large
    }
}

/// A floating circle that shows the presenter while recording, standing where the camera will appear in the video.
/// Drag it to move the presenter; it is never in the recording itself.
@MainActor
final class SelfViewPanel {
    static let shared = SelfViewPanel()
    private var panel: NSPanel?
    /// The part of the screen being recorded, in screen coordinates (origin bottom-left).
    private var area = NSRect.zero
    /// Clear space around the circle, so its shadow is not cut off at the panel's edge.
    static let shadowRoom: CGFloat = 16

    /// The recorded area in screen coordinates, so a spot on screen can be turned into a spot in the video.
    static func area(for target: RecordingTarget) -> NSRect? {
        func screen(_ id: CGDirectDisplayID) -> NSScreen? { NSScreen.screens.first { $0.displayID == id } }
        switch target {
        case .display(let id):
            return screen(id)?.frame
        case .region(let id, let rect):
            guard let frame = screen(id)?.frame else { return nil }
            return NSRect(x: frame.minX + rect.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        case .window(let filter):
            // A window's rectangle is in points from the top-left of the main display.
            guard let main = NSScreen.screens.first?.frame else { return nil }
            let r = filter.contentRect
            return NSRect(x: r.minX, y: main.height - r.maxY, width: r.width, height: r.height)
        }
    }

    func show(camera: CameraSession, over area: NSRect, placement: CameraPlacement?, size: Double) {
        hide()
        guard area.width > 0, area.height > 0 else { return }
        self.area = area
        var bubble = CameraBubble()
        bubble.size = size
        let diameter = (placement?.size ?? size) * area.height
        let room = Self.shadowRoom
        let circle: NSRect
        if let placement {
            circle = NSRect(x: area.minX + placement.x * area.width - diameter / 2,
                            y: area.maxY - placement.y * area.height - diameter / 2, width: diameter, height: diameter)
        } else {
            let corner = bubble.frame(in: area.size)
            circle = NSRect(x: area.minX + corner.minX, y: area.maxY - corner.maxY, width: corner.width, height: corner.height)
        }
        let frame = circle.insetBy(dx: -room, dy: -room)
        let host = NSHostingView(rootView: SelfView(session: camera.session))
        host.frame = NSRect(origin: .zero, size: frame.size)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        // Above the countdown too, so it can be seen and moved while counting down.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.sharingType = .none  // never in the recording
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Where the circle is now, as the video will show it. Nil when it is not showing.
    func placement() -> CameraPlacement? {
        guard let panel, area.width > 0, area.height > 0 else { return nil }
        let frame = panel.frame
        let x = (frame.midX - area.minX) / area.width
        let y = (area.maxY - frame.midY) / area.height
        let diameter = frame.width - 2 * Self.shadowRoom
        return CameraPlacement(x: min(1, max(0, x)), y: min(1, max(0, y)), size: min(CameraBubble.sizeRange.upperBound, diameter / area.height))
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct SelfView: View {
    let session: AVCaptureSessionBox

    init(session: AVCaptureSession) { self.session = AVCaptureSessionBox(session) }

    var body: some View {
        CameraPreview(session: session.session, draggable: true)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .padding(SelfViewPanel.shadowRoom)
            .help("Drag to move where you appear in the video")
    }
}

private struct AVCaptureSessionBox {
    let session: AVCaptureSession
    init(_ session: AVCaptureSession) { self.session = session }
}
