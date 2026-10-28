import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct ShapeModelTests {
    @Test func addingAMarkPutsItAtThePlayheadInsideTheVideo() {
        var project = StudioProject(duration: 10)
        let id = project.addShape(.arrow, at: 2)
        let shape = project.shape(id)!
        #expect(shape.start == 2 && shape.end == 6)
        // Near the end the mark is pulled back so it never runs past the video.
        let late = project.addShape(.box, at: 9.9)
        #expect(project.shape(late)!.end <= 10)
        #expect(project.shape(late)!.length >= ShapeOverlay.minimumLength)
    }

    @Test func aBoxCannotBeSquashedToALineOrDraggedOffThePicture() {
        var project = StudioProject(duration: 10)
        let id = project.addShape(.box, at: 0)
        project.updateShape(id) { $0.x1 = 0.4; $0.x2 = 0.4 }
        let squashed = project.shape(id)!
        #expect(abs(squashed.x2 - squashed.x1) >= ShapeOverlay.minimumSide - 1e-9)
        project.updateShape(id) { $0.x1 = -3; $0.y2 = 7 }
        let clamped = project.shape(id)!
        #expect(clamped.x1 == 0 && clamped.y2 == 1)
    }

    @Test func nudgingKeepsTheMarkTheSameSizeAtTheEdge() {
        var project = StudioProject(duration: 10)
        let id = project.addShape(.box, at: 0)
        let before = project.shape(id)!.rect
        project.nudgeShape(id, byX: 5, y: -5)
        let after = project.shape(id)!.rect
        #expect(abs(after.width - before.width) < 1e-9 && abs(after.height - before.height) < 1e-9)
        #expect(abs(after.maxX - 1) < 1e-9 && abs(after.minY) < 1e-9)
    }

    @Test func aMarkRipplesWithCutsAndVanishesWhenItsStretchIsCut() throws {
        var project = StudioProject(duration: 20)
        let kept = project.addShape(.arrow, at: 10)
        project.updateShape(kept) { $0.start = 10; $0.end = 14 }
        let gone = project.addShape(.box, at: 2)
        project.updateShape(gone) { $0.start = 2; $0.end = 4 }
        try project.remove(TimeSpan(start: 1, end: 5))
        #expect(project.shape(gone) == nil, "a mark whose whole stretch was cut goes with it")
        #expect(project.shape(kept)!.start == 6 && project.shape(kept)!.end == 10)
    }

    @Test func growingTheVideoMakesRoomForMarksAfterIt() {
        var project = StudioProject(duration: 20)
        project.spliceVideoOnly(at: 10)
        _ = project.addShape(.blur, at: 12)
        let id = project.shapes[0].id
        project.updateShape(id) { $0.start = 12; $0.end = 16 }
        // Cut the tail off the first part and pull it back out: the mark moves with the picture.
        let pulledIn = project.moveEdge(ofPart: 0, edge: .end, toSource: 8)
        #expect(pulledIn)
        #expect(project.shape(id)!.start == 10 && project.shape(id)!.end == 14)
        let pulledOut = project.moveEdge(ofPart: 0, edge: .end, toSource: 10)
        #expect(pulledOut)
        #expect(project.shape(id)!.start == 12 && project.shape(id)!.end == 16)
    }

    @Test func aMarkSplitsIntoTwoIdenticalHalves() {
        var project = StudioProject(duration: 10)
        let id = project.addShape(.arrow, at: 0)
        let later = project.splitShape(id, at: 2)
        #expect(later != nil)
        #expect(project.shape(id)!.end == 2 && project.shape(later!)!.start == 2)
        #expect(project.shape(later!)!.x2 == project.shape(id)!.x2)
        #expect(project.splitShape(id, at: 0.1) == nil, "too close to the start for a half to exist")
    }

    @Test func marksCountAsAnEditAndSurviveTheDraft() throws {
        var project = StudioProject(duration: 10)
        #expect(!project.isEdited)
        let id = project.addShape(.blur, at: 1)
        project.setClickHighlights(on: true, clicks: [ClickEvent(time: 3, x: 0.2, y: 0.8)])
        #expect(project.isEdited)

        let store = StudioDraftStore(files: TakeFiles(directory: FileManager.default.temporaryDirectory, baseName: UUID().uuidString))
        let data = try #require(store.encode(StudioDraft(project: project, playhead: 0)))
        let draft = try JSONDecoder.draft.decode(StudioDraft.self, from: data)
        let restored = try #require(draft.project(duration: 10, cameraSource: nil))
        #expect(restored.shape(id) == project.shape(id))
        #expect(restored.clickHighlight?.clicks == [ClickEvent(time: 3, x: 0.2, y: 0.8)])
    }

    @Test func aDraftWrittenBeforeMarksExistedStillOpens() throws {
        // The same fields a draft had before: no "shapes" and no "clickHighlight".
        let old = StudioDraft(project: StudioProject(duration: 10), playhead: 1)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder.draft.encode(old)) as? [String: Any])
        object.removeValue(forKey: "shapes")
        object.removeValue(forKey: "clickHighlight")
        let data = try JSONSerialization.data(withJSONObject: object)
        let draft = try JSONDecoder.draft.decode(StudioDraft.self, from: data)
        let project = try #require(draft.project(duration: 10, cameraSource: nil))
        #expect(project.shapes.isEmpty && project.clickHighlight == nil)
    }
}

private extension JSONEncoder {
    static var draft: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}
private extension JSONDecoder {
    static var draft: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}

@Suite struct ShapeFadeAndGeometryTests {
    @Test func marksFadeInAndOutAndABlurSwitchesQuickly() {
        let arrow = ShapeOverlay(kind: .arrow, start: 2, end: 6, x1: 0, y1: 0, x2: 1, y2: 1)
        #expect(arrow.opacity(at: 1) == 0 && arrow.opacity(at: 7) == 0)
        #expect(arrow.opacity(at: 4) == 1)
        #expect(abs(arrow.opacity(at: 2.075) - 0.5) < 0.001)
        let blur = ShapeOverlay(kind: .blur, start: 2, end: 6, x1: 0, y1: 0, x2: 1, y2: 1)
        #expect(blur.opacity(at: 2.06) >= 0.999, "a blur reaches full strength fast, so a name is never half readable")
    }

    @Test func anArrowHeadSitsAtTheTipAndTheShaftStopsInsideIt() {
        let geometry = ArrowGeometry(from: CGPoint(x: 0.2, y: 0.5), to: CGPoint(x: 0.6, y: 0.5), lineWidth: 0.008, aspect: 16.0 / 9)
        #expect(geometry.tip == CGPoint(x: 0.6, y: 0.5))
        // Pointing right: the wings are behind the tip and either side of the line.
        #expect(geometry.wingA.x < 0.6 && geometry.wingB.x < 0.6)
        #expect(abs(geometry.wingA.x - geometry.wingB.x) < 1e-9)
        #expect(geometry.wingA.y != geometry.wingB.y && abs((geometry.wingA.y + geometry.wingB.y) / 2 - 0.5) < 1e-9)
        #expect(geometry.shaftEnd.x < 0.6 && geometry.shaftEnd.x > geometry.wingA.x)
    }

    @Test func aShortArrowStillGetsASensibleHead() {
        let geometry = ArrowGeometry(from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.5, y: 0.51), lineWidth: 0.02, aspect: 1.5)
        #expect(geometry.shaftEnd.y.isFinite && geometry.wingA.x.isFinite)
        // The head never reaches back past the tail.
        #expect(geometry.wingA.y >= 0.5 - 1e-9 && geometry.wingA.y <= 0.51)
    }
}

@Suite struct ClickRingTests {
    @Test func aRingOpensAndFadesOverItsDuration() {
        let highlight = ClickHighlight(clicks: [ClickEvent(time: 2, x: 0.25, y: 0.75)])
        let timeline = ClickHighlightTimeline(highlight: highlight, cuts: EditModel(duration: 10))
        #expect(timeline.rings(at: 1.9).isEmpty)
        let start = timeline.rings(at: 2.0)
        #expect(start.count == 1 && start[0].x == 0.25 && start[0].y == 0.75)
        let middle = timeline.rings(at: 2 + ClickHighlight.duration / 2)[0]
        #expect(middle.scale > start[0].scale && middle.opacity < start[0].opacity)
        #expect(timeline.rings(at: 2 + ClickHighlight.duration + 0.01).isEmpty)
    }

    @Test func clicksInCutOutSectionsShowNothingAndLaterOnesMove() throws {
        var project = StudioProject(duration: 20)
        project.setClickHighlights(on: true, clicks: [ClickEvent(time: 3, x: 0.1, y: 0.1), ClickEvent(time: 12, x: 0.9, y: 0.9)])
        try project.remove(TimeSpan(start: 2, end: 6))  // takes the click at 3 with it
        let timeline = ClickHighlightTimeline(highlight: project.clickHighlight!, cuts: project.cuts)
        #expect(timeline.moments.count == 1)
        #expect(abs(timeline.moments[0].time - 8) < 1e-6, "the click at 12 s now falls at 8 s")
    }

    @Test func overlappingClicksShowTogether() {
        let highlight = ClickHighlight(clicks: [ClickEvent(time: 1, x: 0.1, y: 0.1), ClickEvent(time: 1.2, x: 0.8, y: 0.8)])
        let timeline = ClickHighlightTimeline(highlight: highlight, cuts: EditModel(duration: 5))
        #expect(timeline.rings(at: 1.3).count == 2)
    }

    @Test func ringSizeIsKeptInRange() {
        #expect(ClickHighlight(clicks: [], size: 5).size == ClickHighlight.sizeRange.upperBound)
        #expect(ClickHighlight(clicks: [], size: 0).size == ClickHighlight.sizeRange.lowerBound)
    }
}

@Suite struct ShownPointTests {
    @Test func aPointRoundTripsThroughABackdropAndAZoom() {
        let canvas = CGSize(width: 1920, height: 1080)
        let background = WindowBackground.standard
        let content = CanvasLayout.contentRect(canvas: canvas, source: canvas, background: background)
        let zoom = ZoomCamera.State(zoom: 2, focusX: 0.7, focusY: 0.4)
        let shown = CanvasLayout.shownPoint(forSource: 0.65, 0.42, content: content, canvas: canvas, zoom: zoom)
        let back = CanvasLayout.sourcePoint(forShown: shown.x, shown.y, content: content, canvas: canvas, zoom: zoom)
        #expect(abs(back.x - 0.65) < 1e-6 && abs(back.y - 0.42) < 1e-6)
    }

    @Test func withNoZoomAndNoBackdropShownIsSource() {
        let canvas = CGSize(width: 800, height: 600)
        let content = CanvasLayout.contentRect(canvas: canvas, source: canvas, background: nil)
        let shown = CanvasLayout.shownPoint(forSource: 0.3, 0.6, content: content, canvas: canvas, zoom: ZoomCamera.State(zoom: 1, focusX: 0.5, focusY: 0.5))
        #expect(abs(shown.x - 0.3) < 1e-9 && abs(shown.y - 0.6) < 1e-9)
    }
}

@Suite(.serialized) struct AnnotationRenderTests {
    /// Black and white stripes across the whole picture, so a blur has something to smooth.
    private func stripes(width: Int, height: Int) -> CIImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for column in stride(from: 0, to: width, by: 2) {
            context.setFillColor(CGColor(gray: (column / 2) % 2 == 0 ? 1 : 0, alpha: 1))
            context.fill(CGRect(x: column, y: 0, width: 2, height: height))
        }
        return CIImage(cgImage: context.makeImage()!)
    }

    private func render(_ image: CIImage, size: CGSize) -> CGImage {
        CIContext().createCGImage(image, from: CGRect(origin: .zero, size: size))!
    }

    /// Brightest minus darkest sample in a region (0...255).
    private func range(of image: CGImage, region: CGRect) -> Double {
        var low = 255.0, high = 0.0
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for row in Int(region.minY * Double(height))..<Int(region.maxY * Double(height)) {
            for column in Int(region.minX * Double(width))..<Int(region.maxX * Double(width)) {
                let value = Double(data[(row * width + column) * 4])
                low = min(low, value); high = max(high, value)
            }
        }
        return high - low
    }

    @Test func aBlurSmoothsItsRegionAndLeavesTheRestAlone() throws {
        let canvas = CGSize(width: 400, height: 200)
        let blur = ShapeOverlay(kind: .blur, start: 0, end: 5, x1: 0.25, y1: 0.25, x2: 0.75, y2: 0.75, blurRadius: 0.04)
        let layer = try #require(AnnotationLayer(
            canvas: canvas, content: CGRect(origin: .zero, size: canvas), shapes: [blur], highlight: nil, cuts: nil))
        let result = render(layer.draw(over: stripes(width: 400, height: 200), at: 2), size: canvas)
        #expect(range(of: result, region: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)) < 90, "inside the blur the stripes smear together")
        #expect(range(of: result, region: CGRect(x: 0.02, y: 0.02, width: 0.15, height: 0.15)) > 240, "outside it they are untouched")
        let before = render(layer.draw(over: stripes(width: 400, height: 200), at: 9), size: canvas)
        #expect(range(of: before, region: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)) > 240, "after the mark ends the picture is clear again")
    }

    @Test func aBlurFollowsTheWindowIntoABackdrop() throws {
        let canvas = CGSize(width: 400, height: 200)
        let content = CanvasLayout.contentRect(canvas: canvas, source: canvas, background: .standard)
        #expect(content.minX > 5, "the window is inset")
        let blur = ShapeOverlay(kind: .blur, start: 0, end: 5, x1: 0, y1: 0, x2: 1, y2: 1, blurRadius: 0.04)
        let layer = try #require(AnnotationLayer(canvas: canvas, content: content, shapes: [blur], highlight: nil, cuts: nil))
        let cleared = layer.draw(over: stripes(width: 400, height: 200), at: 2)
        // The blur covers exactly the window's rectangle, not the canvas: the corner outside it stays sharp.
        let result = render(cleared, size: canvas)
        #expect(range(of: result, region: CGRect(x: 0, y: 0, width: content.minX / canvas.width * 0.6, height: 0.1)) > 240)
    }

    @Test func nothingToDrawMakesNoLayer() {
        let canvas = CGSize(width: 100, height: 100)
        #expect(AnnotationLayer(canvas: canvas, content: CGRect(origin: .zero, size: canvas), shapes: [], highlight: nil, cuts: nil) == nil)
    }

    @Test func aBoxIsDrawnIntoTheSavedPictureOnlyWhileItShows() async throws {
        let source = try await TestMedia.video(seconds: 4, color: (20, 30, 120))
        var project = StudioProject(duration: 4)
        let id = project.addShape(.box, at: 1)
        project.updateShape(id) {
            $0.start = 1; $0.end = 3; $0.x1 = 0.3; $0.x2 = 0.7; $0.y1 = 0.3; $0.y2 = 0.7
            $0.color = TextColor(red: 1, green: 0, blue: 0); $0.lineWidth = ShapeOverlay.lineWidthRange.upperBound
        }
        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: project, to: out) { _ in }
        // The left edge of the box is a thick red line.
        let edge = CGRect(x: 0.28, y: 0.45, width: 0.04, height: 0.1)
        let showing = try await TestMedia.channels(of: out, at: 2, region: edge)
        let hidden = try await TestMedia.channels(of: out, at: 3.7, region: edge)
        #expect(showing.red > hidden.red + 40, "the box draws red on the edge: \(showing.red) vs \(hidden.red)")
        // Inside the box nothing is covered.
        let inside = try await TestMedia.channels(of: out, at: 2, region: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1))
        #expect(abs(inside.red - hidden.red) < 12)
    }

    @Test func anArrowIsDrawnIntoTheSavedPicture() async throws {
        let source = try await TestMedia.video(seconds: 3, color: (20, 30, 120))
        var project = StudioProject(duration: 3)
        let id = project.addShape(.arrow, at: 0)
        project.updateShape(id) {
            $0.start = 0; $0.end = 3; $0.x1 = 0.2; $0.y1 = 0.5; $0.x2 = 0.8; $0.y2 = 0.5
            $0.color = TextColor(red: 1, green: 0.9, blue: 0); $0.lineWidth = ShapeOverlay.lineWidthRange.upperBound
        }
        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: project, to: out) { _ in }
        let shaft = try await TestMedia.channels(of: out, at: 1.5, region: CGRect(x: 0.4, y: 0.48, width: 0.1, height: 0.04))
        let away = try await TestMedia.channels(of: out, at: 1.5, region: CGRect(x: 0.4, y: 0.1, width: 0.1, height: 0.04))
        #expect(shaft.red > away.red + 60 && shaft.green > away.green + 60, "yellow shaft on blue: \(shaft) vs \(away)")
    }

    @Test func clickRingsAppearAtTheClickAndFadeAway() async throws {
        let source = try await TestMedia.video(seconds: 4, color: (20, 30, 120))
        var project = StudioProject(duration: 4)
        project.setClickHighlights(on: true, clicks: [ClickEvent(time: 1, x: 0.5, y: 0.5)])
        project.clickHighlight?.size = ClickHighlight.sizeRange.upperBound
        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: project, to: out) { _ in }
        // Half way through, the ring is about 0.07 of the picture's height out from the click.
        let area = CGRect(x: 0.43, y: 0.43, width: 0.14, height: 0.14)
        let before = try await TestMedia.channels(of: out, at: 0.5, region: area)
        let during = try await TestMedia.channels(of: out, at: 1.3, region: area)
        let after = try await TestMedia.channels(of: out, at: 2.5, region: area)
        #expect(during.red > before.red + 12, "a yellow ring tints the area: \(during.red) vs \(before.red)")
        #expect(abs(after.red - before.red) < 3, "and is gone afterwards")
    }

    @Test func marksStayOnTheirPlaceWhenAZoomMagnifiesThePicture() async throws {
        let source = try await TestMedia.video(seconds: 4, color: (20, 30, 120))
        var project = StudioProject(duration: 4)
        let zoom = project.addZoom(at: 0, scale: 2)
        project.updateZoom(zoom) { $0.start = 0; $0.end = 4; $0.x = 0.25; $0.y = 0.5 }
        let id = project.addShape(.box, at: 0)
        project.updateShape(id) {
            $0.start = 0; $0.end = 4; $0.x1 = 0.2; $0.x2 = 0.3; $0.y1 = 0.4; $0.y2 = 0.6
            $0.color = TextColor(red: 1, green: 0, blue: 0); $0.lineWidth = ShapeOverlay.lineWidthRange.upperBound
        }
        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: project, to: out) { _ in }
        // Zoomed 2× on (0.25, 0.5): the box (0.2–0.3 across) now spans 0.4–0.6 of the screen, and its left edge sits at 0.4.
        let edge = CGRect(x: 0.38, y: 0.5, width: 0.05, height: 0.1)
        let elsewhere = CGRect(x: 0.8, y: 0.5, width: 0.05, height: 0.1)
        let at = try await TestMedia.channels(of: out, at: 2, region: edge)
        let off = try await TestMedia.channels(of: out, at: 2, region: elsewhere)
        #expect(at.red > off.red + 30, "the box moved with the zoom: \(at.red) vs \(off.red)")
    }
}

@Suite struct ShapeLaneTests {
    @Test func marksThatOverlapGetTheirOwnLanes() {
        var project = StudioProject(duration: 20)
        let a = project.addShape(.arrow, at: 1); project.updateShape(a) { $0.start = 1; $0.end = 6 }
        let b = project.addShape(.box, at: 2); project.updateShape(b) { $0.start = 2; $0.end = 7 }
        let c = project.addShape(.blur, at: 8); project.updateShape(c) { $0.start = 8; $0.end = 9 }
        let lanes = project.shapeLanes()
        #expect(lanes[a] == 0 && lanes[b] == 1 && lanes[c] == 0, "the third starts after the first ended, so it reuses lane 0")
    }
}
