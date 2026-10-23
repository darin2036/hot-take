import AVFoundation
import CoreGraphics
import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct CameraBubbleTests {
    @Test func cornersTuckTheBubbleInByAMargin() {
        let canvas = CGSize(width: 1600, height: 900)
        var bubble = CameraBubble()
        bubble.size = 0.2
        let margin = CameraBubble.margin * 900
        let left = bubble.frame(in: canvas)
        #expect(abs(left.width - 180) < 0.001 && abs(left.minX - margin) < 0.001 && abs(left.maxY - (900 - margin)) < 0.001)
        bubble.corner = .topRight
        let right = bubble.frame(in: canvas)
        #expect(abs(right.maxX - (1600 - margin)) < 0.001 && abs(right.minY - margin) < 0.001)
    }

    @Test func aDraggedBubbleKeepsItsPlaceAndStaysInsideThePicture() {
        let canvas = CGSize(width: 1600, height: 900)
        var bubble = CameraBubble()
        bubble.move(toX: 0.5, y: 0.5)
        #expect(bubble.corner == nil)
        let middle = bubble.frame(in: canvas)
        #expect(abs(middle.midX - 800) < 0.001 && abs(middle.midY - 450) < 0.001)
        bubble.move(toX: 1.4, y: -3)  // dropped past an edge
        let edge = bubble.frame(in: canvas)
        #expect(edge.maxX <= 1600 && edge.minY >= 0)
    }

    @Test func sizesAndNudgesAreHeldToTheirRanges() {
        var bubble = CameraBubble()
        bubble.size = 9
        bubble.nudge = -50
        bubble.clamp()
        #expect(bubble.size == CameraBubble.sizeRange.upperBound && bubble.nudge == CameraBubble.nudgeRange.lowerBound)
    }

    @Test func aBubbleNeverGrowsBeyondAShortPicture() {
        var bubble = CameraBubble()
        bubble.size = 0.5
        let tall = bubble.frame(in: CGSize(width: 200, height: 900))
        #expect(tall.width <= 200)
    }
}

@Suite struct CameraTimelineTests {
    private let kept = [TimeSpan(start: 0, end: 4), TimeSpan(start: 6, end: 10)]

    @Test func aCameraThatStartedLaterHasNothingBeforeItBegins() {
        let pieces = CameraTimeline.pieces(for: kept, offset: 2, cameraDuration: 20)
        #expect(pieces[0] == CameraTimeline.Piece(cameraStart: 0, length: 2, delay: 2))  // screen 2–4 is camera 0–2
        #expect(pieces[1] == CameraTimeline.Piece(cameraStart: 4, length: 4, delay: 0))  // screen 6–10 is camera 4–8
    }

    @Test func aCameraThatStartedFirstSkipsItsOwnLeadIn() {
        let pieces = CameraTimeline.pieces(for: [TimeSpan(start: 0, end: 5)], offset: -1.5, cameraDuration: 20)
        #expect(pieces[0] == CameraTimeline.Piece(cameraStart: 1.5, length: 5, delay: 0))
    }

    @Test func footageThatRunsOutEndsTheBubbleEarly() {
        let pieces = CameraTimeline.pieces(for: [TimeSpan(start: 0, end: 10)], offset: 0, cameraDuration: 6)
        #expect(pieces[0]?.length == 6)
        #expect(CameraTimeline.pieces(for: [TimeSpan(start: 8, end: 10)], offset: 0, cameraDuration: 6)[0] == nil)
    }

    @Test func theNudgeShiftsTheCamera() {
        let plain = CameraTimeline.pieces(for: [TimeSpan(start: 5, end: 8)], offset: 1, cameraDuration: 20)[0]
        let nudged = CameraTimeline.pieces(for: [TimeSpan(start: 5, end: 8)], offset: 1, nudge: 0.5, cameraDuration: 20)[0]
        #expect(plain?.cameraStart == 4 && nudged?.cameraStart == 3.5)
    }
}

@Suite struct CameraFilesTests {
    @Test func originalsLiveInAHiddenFolderBesideTheTake() {
        let files = TakeFiles(directory: URL(fileURLWithPath: "/tmp/lib/Folder"), baseName: "Take")
        #expect(files.screenOriginal.path == "/tmp/lib/Folder/.hot-take-originals/Take.screen.mp4")
        #expect(files.cameraOriginal.path == "/tmp/lib/Folder/.hot-take-originals/Take.camera.mov")
    }

    @Test func aPlacementChosenWhileRecordingRoundTripsAndStartsTheProject() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("place-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = TakeFiles(directory: root, baseName: "Take")
        let placement = CameraPlacement(x: 0.8, y: 0.2, size: 0.3)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try TakeLibrary.saveCapture(for: files, created: Date(), clicks: [], kind: "screen", cameraOffset: 0.4, cameraPlacement: placement)
        #expect(TakeLibrary.metadata(for: files)?.cameraPlacement == placement)

        let source = CameraSource(url: files.cameraOriginal, offset: 0.4, placement: placement)
        let project = StudioProject(duration: 10, cameraSource: source)
        #expect(project.camera.corner == nil)
        #expect(project.camera.x == 0.8 && project.camera.y == 0.2 && project.camera.size == 0.3)
        #expect(!project.isEdited)
    }

    @Test func movingAndTrashingATakeCarriesItsOriginals() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cam-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Dest"), withIntermediateDirectories: true)
        let files = TakeFiles(directory: root, baseName: "Take")
        try FileManager.default.createDirectory(at: files.originalsDirectory, withIntermediateDirectories: true)
        for url in [files.video, files.screenOriginal, files.cameraOriginal] { try Data("x".utf8).write(to: url) }
        let entry = try #require(TakeLibrary.load(directory: root).first)
        #expect(TakeLibrary.load(directory: root).count == 1)  // the hidden originals are not takes of their own

        let moved = try TakeLibrary.move(entry, toFolder: "Dest", root: root)
        #expect(FileManager.default.fileExists(atPath: moved.screenOriginal.path))
        #expect(FileManager.default.fileExists(atPath: moved.cameraOriginal.path))
        #expect(!FileManager.default.fileExists(atPath: files.cameraOriginal.path))
    }

    @Test func theCameraOffsetSurvivesTheNotesFile() throws {
        var metadata = TakeMetadata(title: "t", summary: "", created: Date(timeIntervalSince1970: 1_700_000_000))
        metadata.cameraOffset = 0.12
        let again = try TakeMetadata.decode(metadata.encoded())
        #expect(again.cameraOffset == 0.12)
        var rewritten = TakeMetadata(title: "new", summary: "", created: metadata.created)
        rewritten.keepCapture(of: again)
        #expect(rewritten.cameraOffset == 0.12)
        #expect(try TakeMetadata.decode(Data(#"{"title":"x","summary":"","created":"2023-11-14T22:13:20Z"}"#.utf8)).cameraOffset == nil)
    }

    @Test func aProjectWithACameraIsNotEditedUntilSomethingChanges() {
        let source = CameraSource(url: URL(fileURLWithPath: "/tmp/c.mov"), offset: 0)
        var project = StudioProject(duration: 10, cameraSource: source)
        #expect(!project.isEdited)
        project.camera.isVisible = false
        #expect(project.isEdited)
    }
}

@Suite(.serialized) struct CameraRenderTests {
    private func bubbleCentre(_ size: CGSize) -> CGRect {
        let frame = CameraBubble().frame(in: size)
        return CGRect(x: (frame.midX - 8) / size.width, y: (frame.midY - 8) / size.height, width: 16 / size.width, height: 16 / size.height)
    }

    private func green(_ c: (red: Double, green: Double, blue: Double)) -> Bool { c.green > 120 && c.blue < 90 && c.red < 90 }
    private func blue(_ c: (red: Double, green: Double, blue: Double)) -> Bool { c.blue > 80 && c.green < 90 && c.red < 70 }

    @Test func theCameraAppearsInItsBubbleOnlyWhileItHasFootage() async throws {
        let screen = try await TestMedia.video(seconds: 8, color: (20, 30, 120))
        let camera = try await TestMedia.video(seconds: 4, color: (30, 200, 40))  // starts 1 s after the screen
        let size = try #require(try await AVURLAsset(url: screen).loadTracks(withMediaType: .video).first?.load(.naturalSize))
        let project = StudioProject(duration: 8, cameraSource: CameraSource(url: camera, offset: 1))
        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: screen), project: project, to: out) { _ in }
        let spot = bubbleCentre(size)
        let before = try await TestMedia.channels(of: out, at: 0.5, region: spot)
        let during = try await TestMedia.channels(of: out, at: 3, region: spot)
        let after = try await TestMedia.channels(of: out, at: 6.5, region: spot)
        #expect(blue(before), "no camera yet: \(before)")
        #expect(green(during), "camera showing: \(during)")
        #expect(blue(after), "camera has ended: \(after)")
        // The rest of the picture is untouched.
        let away = try await TestMedia.channels(of: out, at: 3, region: CGRect(x: 0.6, y: 0.1, width: 0.2, height: 0.2))
        #expect(blue(away))
    }

    @Test func hidingTheCameraLeavesJustTheScreen() async throws {
        let screen = try await TestMedia.video(seconds: 4, color: (20, 30, 120))
        let camera = try await TestMedia.video(seconds: 4, color: (30, 200, 40))
        var project = StudioProject(duration: 4, cameraSource: CameraSource(url: camera, offset: 0))
        project.camera.isVisible = false
        let output = try await StudioComposer.build(asset: AVURLAsset(url: screen), project: project, burnText: true)
        #expect(output.videoComposition == nil)  // nothing to draw, so the picture goes through untouched
    }

    @Test func aCutCarriesTheCameraWithTheScreenAndAMovedBubbleGoesWhereItWasPut() async throws {
        let screen = try await TestMedia.video(seconds: 8, color: (20, 30, 120))
        let camera = try await TestMedia.video(seconds: 8, color: (30, 200, 40))
        let size = try #require(try await AVURLAsset(url: screen).loadTracks(withMediaType: .video).first?.load(.naturalSize))
        var project = StudioProject(duration: 8, cameraSource: CameraSource(url: camera, offset: 0))
        try project.remove(TimeSpan(start: 2, end: 4))  // 6 s left
        project.camera.corner = .topRight
        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: screen), project: project, to: out) { _ in }
        #expect(abs(try await TestMedia.duration(of: out) - 6) < 0.25)
        let frame = project.camera.frame(in: size)
        let topRight = CGRect(x: (frame.midX - 8) / size.width, y: (frame.midY - 8) / size.height, width: 16 / size.width, height: 16 / size.height)
        #expect(green(try await TestMedia.channels(of: out, at: 3, region: topRight)))
        let oldPlace = bubbleCentre(size)
        #expect(blue(try await TestMedia.channels(of: out, at: 3, region: oldPlace)))
    }
}
