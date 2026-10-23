import AVFoundation
import CoreGraphics
import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct ZoomCameraTests {
    private let zoom = ZoomSegment(start: 2, end: 6, x: 0.8, y: 0.3, scale: 2)

    @Test func easesInHoldsAndEasesOut() {
        #expect(ZoomCamera.state(at: 1, zooms: [zoom]).zoom == 1)
        #expect(ZoomCamera.state(at: 2, zooms: [zoom]).zoom == 1)
        let early = ZoomCamera.state(at: 2.3, zooms: [zoom]).zoom
        #expect(early > 1 && early < 2)
        #expect(ZoomCamera.state(at: 4, zooms: [zoom]).zoom == 2)
        let late = ZoomCamera.state(at: 5.7, zooms: [zoom]).zoom
        #expect(late > 1 && late < 2)
        #expect(ZoomCamera.state(at: 7, zooms: [zoom]).zoom == 1)
        let held = ZoomCamera.state(at: 4, zooms: [zoom])
        #expect(held.focusX == 0.8 && held.focusY == 0.3)
    }

    @Test func zoomingNeverStepsBackwardsWhileEasingIn() {
        var last = 1.0
        for step in 0...30 {
            let value = ZoomCamera.state(at: 2 + Double(step) * 0.02, zooms: [zoom]).zoom
            #expect(value >= last - 1e-9)
            last = value
        }
    }

    @Test func aVeryShortZoomStillReachesFullStrength() {
        let short = ZoomSegment(start: 1, end: 2, scale: 2)  // ramps are limited to half its length
        #expect(abs(ZoomCamera.state(at: 1.5, zooms: [short]).zoom - 2) < 1e-9)
    }

    @Test func theCropStaysInsideThePicture() {
        let corner = ZoomCamera.crop(zoom: 2, focusX: 1, focusY: 0)  // looking at the top-right corner
        #expect(corner == CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        let middle = ZoomCamera.crop(zoom: 2, focusX: 0.5, focusY: 0.5)
        #expect(middle == CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(ZoomCamera.crop(zoom: 1, focusX: 0.9, focusY: 0.1) == CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

@Suite struct ZoomGeneratorTests {
    @Test func closeClicksShareOneZoomAndFarOnesGetTheirOwn() {
        let clicks = [
            ClickEvent(time: 3, x: 0.2, y: 0.2), ClickEvent(time: 4, x: 0.4, y: 0.4),  // one group, centered at 0.3
            ClickEvent(time: 12, x: 0.9, y: 0.5),
        ]
        let zooms = ZoomGenerator.segments(clicks: clicks, cuts: EditModel(duration: 20))
        #expect(zooms.count == 2)
        #expect(abs(zooms[0].x - 0.3) < 1e-9 && abs(zooms[0].y - 0.3) < 1e-9)
        #expect(zooms[0].start < 3 && zooms[0].end > 4)
        #expect(abs(zooms[1].x - 0.9) < 1e-9)
        #expect(zooms[0].end <= zooms[1].start)
    }

    @Test func clicksInCutOutPartsAreIgnoredAndTheRestMoveWithTheEdit() throws {
        var cuts = EditModel(duration: 20)
        try cuts.remove(TimeSpan(start: 2, end: 6))  // the 3 s and 4 s clicks are gone
        let clicks = [ClickEvent(time: 3, x: 0.1, y: 0.1), ClickEvent(time: 10, x: 0.6, y: 0.6)]
        let zooms = ZoomGenerator.segments(clicks: clicks, cuts: cuts)
        #expect(zooms.count == 1)
        #expect(zooms[0].start > 5 && zooms[0].start < 6.5)  // the click at 10 s is now at 6 s
    }

    @Test func zoomsStayInsideTheVideoAndNeverOverlap() {
        let clicks = [ClickEvent(time: 0.1, x: 0.5, y: 0.5), ClickEvent(time: 19.9, x: 0.5, y: 0.5)]
        let zooms = ZoomGenerator.segments(clicks: clicks, cuts: EditModel(duration: 20))
        #expect(zooms.allSatisfy { $0.start >= 0 && $0.end <= 20 })
        #expect(ZoomGenerator.segments(clicks: [], cuts: EditModel(duration: 20)).isEmpty)
    }
}

@Suite struct CanvasLayoutTests {
    @Test func withoutABackgroundTheWindowFillsThePicture() {
        let canvas = CGSize(width: 1600, height: 900)
        #expect(CanvasLayout.contentRect(canvas: canvas, source: canvas, background: nil) == CGRect(origin: .zero, size: canvas))
    }

    @Test func theWindowShrinksToLeaveAMarginAndStaysCenterd() {
        let canvas = CGSize(width: 1600, height: 900)
        let background = WindowBackground(top: .white, bottom: .black, padding: 0.1)
        let rect = CanvasLayout.contentRect(canvas: canvas, source: canvas, background: background)
        #expect(abs(rect.midX - 800) < 0.5 && abs(rect.midY - 450) < 0.5)
        #expect(rect.minY >= 90 - 0.5)  // a tenth of the shorter side on every side
        #expect(abs(rect.width / rect.height - 16.0 / 9) < 0.01)
    }

    @Test func aTallWindowInAWideCanvasKeepsItsShape() {
        let rect = CanvasLayout.contentRect(
            canvas: CGSize(width: 1600, height: 900), source: CGSize(width: 600, height: 900), background: .standard)
        #expect(abs(rect.width / rect.height - 600.0 / 900) < 0.01)
        #expect(rect.minX > 0 && rect.maxX < 1600)
    }

    @Test func pointsMapBetweenTheWindowAndThePictureBothWays() {
        let canvas = CGSize(width: 1000, height: 500)
        let content = CGRect(x: 100, y: 50, width: 800, height: 400)
        let point = CanvasLayout.canvasPoint(forSource: 0.5, 0.5, content: content, canvas: canvas)
        #expect(abs(point.x - 0.5) < 1e-9 && abs(point.y - 0.5) < 1e-9)
        let back = CanvasLayout.sourcePoint(forCanvas: point.x, point.y, content: content, canvas: canvas)
        #expect(abs(back.x - 0.5) < 1e-9 && abs(back.y - 0.5) < 1e-9)
        #expect(CanvasLayout.sourcePoint(forCanvas: 0, 0, content: content, canvas: canvas) == CGPoint(x: 0, y: 0))  // clamped
    }

    @Test func settingsAreClampedToSensibleRanges() {
        let wild = WindowBackground(top: .white, bottom: .black, padding: 5, cornerRadius: -1)
        #expect(wild.padding == WindowBackground.paddingRange.upperBound && wild.cornerRadius == 0)
        #expect(WindowBackground(top: .white, bottom: .white).isSolid)
    }
}

@Suite struct StudioZoomEditTests {
    @Test func cutsRippleZoomsLikeText() throws {
        var project = StudioProject(duration: 20)
        let id = project.addZoom(at: 10)
        try project.remove(TimeSpan(start: 2, end: 6))
        let moved = try #require(project.zoom(id))
        #expect(abs(moved.start - 6) < 1e-6)
        let doomed = project.addZoom(at: 3)
        try project.remove(TimeSpan(start: 2, end: 8))  // swallows the whole zoom
        #expect(project.zoom(doomed) == nil)
    }

    @Test func zoomsAreEditedWithinTheVideoAndCountAsAnEdit() {
        var project = StudioProject(duration: 10)
        #expect(!project.isEdited)
        let id = project.addZoom(at: 9.5)
        #expect(project.isEdited)
        let zoom = project.zoom(id)!
        #expect(zoom.end <= 10 && zoom.length >= ZoomSegment.minimumLength)
        project.updateZoom(id) { $0.scale = 99; $0.x = -3 }
        #expect(project.zoom(id)!.scale == ZoomSegment.scaleRange.upperBound && project.zoom(id)!.x == 0)
        project.moveZoom(id, to: 100)
        #expect(project.zoom(id)!.end <= 10)
        project.removeZoom(id)
        #expect(project.zooms.isEmpty)
    }

    @Test func generatingZoomsReplacesTheOldOnes() {
        var project = StudioProject(duration: 20)
        project.addZoom(at: 1)
        project.generateZooms(from: [ClickEvent(time: 10, x: 0.2, y: 0.8)])
        #expect(project.zooms.count == 1 && abs(project.zooms[0].x - 0.2) < 1e-9)
    }

    @Test func clicksAndCaptureKindSurviveTheSidecarAndOldSidecarsStillLoad() throws {
        var metadata = TakeMetadata(title: "t", summary: "", created: Date(timeIntervalSince1970: 1_700_000_000))
        metadata.clicks = [ClickEvent(time: 1.5, x: 0.25, y: 0.75)]
        metadata.captureKind = "window"
        let again = try TakeMetadata.decode(metadata.encoded())
        #expect(again.clicks == metadata.clicks && again.captureKind == "window")
        let old = #"{"title":"x","summary":"","created":"2023-11-14T22:13:20Z"}"#
        let loaded = try TakeMetadata.decode(Data(old.utf8))
        #expect(loaded.clicks.isEmpty && loaded.captureKind == nil)
        var rewritten = TakeMetadata(title: "new", summary: "s", created: metadata.created)
        rewritten.keepCapture(of: metadata)
        #expect(rewritten.clicks.count == 1 && rewritten.captureKind == "window")
    }
}

@Suite(.serialized) struct StudioEffectsRenderTests {
    private let corner = CGRect(x: 0, y: 0, width: 0.05, height: 0.05)
    private let center = CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)

    private func red(_ c: (red: Double, green: Double, blue: Double)) -> Bool { c.red > 180 && c.blue < 80 }
    private func blue(_ c: (red: Double, green: Double, blue: Double)) -> Bool { c.blue > 80 && c.red < 70 }

    @Test func theWindowSitsOnTheBackdropInTheSavedVideo() async throws {
        let source = try await TestMedia.video(seconds: 3, color: (20, 30, 120))
        var project = StudioProject(duration: 3)
        project.background = WindowBackground(top: TextColor(red: 1, green: 0, blue: 0), bottom: TextColor(red: 1, green: 0, blue: 0), padding: 0.15, cornerRadius: 0, shadow: false)
        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: project, to: out) { _ in }
        let edge = try await TestMedia.channels(of: out, at: 1, region: corner)
        let middle = try await TestMedia.channels(of: out, at: 1, region: center)
        #expect(red(edge), "the margin should be the backdrop color: \(edge)")
        #expect(blue(middle), "the window should be in the middle: \(middle)")
        #expect(abs(try await TestMedia.duration(of: out) - 3) < 0.2)
    }

    @Test func aZoomFillsThePictureWithTheWindowOnlyWhileItLasts() async throws {
        let source = try await TestMedia.video(seconds: 6, color: (20, 30, 120))
        var project = StudioProject(duration: 6)
        project.background = WindowBackground(top: TextColor(red: 1, green: 0, blue: 0), bottom: TextColor(red: 1, green: 0, blue: 0), padding: 0.15, cornerRadius: 0, shadow: false)
        project.zooms = [ZoomSegment(start: 2, end: 5, x: 0.5, y: 0.5, scale: 3)]
        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: project, to: out) { _ in }
        let before = try await TestMedia.channels(of: out, at: 0.8, region: corner)
        let during = try await TestMedia.channels(of: out, at: 3.5, region: corner)
        let after = try await TestMedia.channels(of: out, at: 5.6, region: corner)
        #expect(red(before), "before the zoom the margin shows: \(before)")
        #expect(blue(during), "zoomed in, the window fills the corner: \(during)")
        #expect(red(after), "after it eases out the margin is back: \(after)")
    }

    @Test func zoomWorksWithoutABackdropAndKeepsTheSize() async throws {
        let source = try await TestMedia.video(seconds: 4, color: (20, 30, 120))
        var project = StudioProject(duration: 4)
        project.zooms = [ZoomSegment(start: 1, end: 3, scale: 2)]
        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: project, to: out) { _ in }
        let size = try await AVURLAsset(url: out).loadTracks(withMediaType: .video).first?.load(.naturalSize)
        let original = try await AVURLAsset(url: source).loadTracks(withMediaType: .video).first?.load(.naturalSize)
        #expect(size == original)
        #expect(blue(try await TestMedia.channels(of: out, at: 2, region: center)))
    }

    @Test func thePreviewShowsTheBackdropAndTheZoomToo() async throws {
        let source = try await TestMedia.video(seconds: 4, color: (20, 30, 120))
        var project = StudioProject(duration: 4)
        project.background = WindowBackground(top: TextColor(red: 1, green: 0, blue: 0), bottom: TextColor(red: 1, green: 0, blue: 0), padding: 0.15, cornerRadius: 0, shadow: false)
        let output = try await StudioComposer.build(asset: AVURLAsset(url: source), project: project, burnText: false)
        #expect(output.videoComposition != nil)
        let plain = try await StudioComposer.build(asset: AVURLAsset(url: source), project: StudioProject(duration: 4), burnText: false)
        #expect(plain.videoComposition == nil)  // an unedited preview needs no extra drawing
    }
}
