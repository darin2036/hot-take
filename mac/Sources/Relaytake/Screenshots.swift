import AppKit
import CoreGraphics
import RelaytakeCore
import ScreenCaptureKit

/// Takes one picture of a screen, window or area with the same source choices as recording, and keeps Hot Take's
/// own windows (and, if asked, Notification Center) out of it.
@MainActor
enum ScreenshotTaker {
    static func capture(_ target: RecordingTarget, hideNotifications: Bool) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let leftOut = Set(CaptureExclusions.bundleIdentifiers(
            ownApp: Bundle.main.bundleIdentifier, includeOwnApp: false, hideNotifications: hideNotifications))
        let excluded = content.applications.filter { leftOut.contains($0.bundleIdentifier) }

        func display(_ id: CGDirectDisplayID) throws -> SCDisplay {
            guard let found = content.displays.first(where: { $0.displayID == id }) else { throw RecorderError.noDisplay }
            return found
        }
        let filter: SCContentFilter
        var sourceRect: CGRect?
        switch target {
        case .display(let id):
            filter = SCContentFilter(display: try display(id), excludingApplications: excluded, exceptingWindows: [])
        case .region(let id, let rect):
            filter = SCContentFilter(display: try display(id), excludingApplications: excluded, exceptingWindows: [])
            sourceRect = rect
        case .window(let selected):
            filter = selected
        }
        let configuration = SCStreamConfiguration()
        let pixels = CaptureGeometry.evenPixelSize(points: sourceRect?.size ?? filter.contentRect.size, scale: CGFloat(filter.pointPixelScale))
        configuration.width = pixels.width
        configuration.height = pixels.height
        if let sourceRect { configuration.sourceRect = sourceRect }
        configuration.showsCursor = false
        if case .window = target { configuration.ignoreShadowsSingleWindow = true }
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
