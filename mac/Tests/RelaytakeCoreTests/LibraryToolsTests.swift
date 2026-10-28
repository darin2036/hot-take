import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import RelaytakeCore

@Suite struct JoinPlanTests {
    @Test func theJoinedPictureIsTheLargestWidthAndHeightMadeEven() {
        #expect(JoinPlan.renderSize(for: [CGSize(width: 1920, height: 1080), CGSize(width: 1280, height: 720)]) == CGSize(width: 1920, height: 1080))
        #expect(JoinPlan.renderSize(for: [CGSize(width: 1001, height: 563)]) == CGSize(width: 1002, height: 564))
        #expect(JoinPlan.renderSize(for: []) == CGSize(width: 2, height: 2))
    }

    @Test func onlyClipsOfDifferentSizesNeedEncoding() {
        let hd = CGSize(width: 1920, height: 1080)
        #expect(!JoinPlan.needsReencode(sizes: [hd, hd, CGSize(width: 1920.5, height: 1080)]))
        #expect(JoinPlan.needsReencode(sizes: [hd, CGSize(width: 1280, height: 720)]))
        #expect(!JoinPlan.needsReencode(sizes: []))
    }

    @Test func aSmallerClipIsCenteredWithBarsNotStretched() {
        let canvas = CGSize(width: 1920, height: 1080)
        let narrow = CGSize(width: 540, height: 1080)  // portrait strip
        let placed = CGRect(origin: .zero, size: narrow).applying(JoinPlan.fit(narrow, into: canvas))
        #expect(abs(placed.height - 1080) < 1e-6 && abs(placed.width - 540) < 1e-6)
        #expect(abs(placed.midX - 960) < 1e-6)
        let small = CGSize(width: 960, height: 540)
        let scaled = CGRect(origin: .zero, size: small).applying(JoinPlan.fit(small, into: canvas))
        #expect(abs(scaled.width - 1920) < 1e-6 && abs(scaled.height - 1080) < 1e-6)
    }

    @Test func titlesStayShort() {
        #expect(JoinPlan.title(for: []) == "Joined takes")
        #expect(JoinPlan.title(for: ["A", "B"]) == "A + B")
        #expect(JoinPlan.title(for: ["A", "B", "C", "D"]) == "A + B + 2 more")
        #expect(JoinPlan.title(for: [String(repeating: "x", count: 60), "B"]).count < 40)
    }
}

@Suite(.serialized) struct TakeJoinerTests {
    @Test func recordingsOfTheSameSizeJoinEndToEndWithTheirSound() async throws {
        let first = try await TestMedia.video(seconds: 2, color: (200, 20, 20), toneHz: 440)
        let second = try await TestMedia.video(seconds: 3, color: (20, 200, 20), toneHz: 880)
        let out = TestMedia.tempURL("mp4")
        try await TakeJoiner.join([first, second], to: out)
        let length = try await TestMedia.duration(of: out)
        #expect(abs(length - 5) < 0.3, "2 s + 3 s: \(length)")
        // The picture changes colour where the second clip starts, and the sound carries on.
        let early = try await TestMedia.channels(of: out, at: 1, region: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4))
        let late = try await TestMedia.channels(of: out, at: 4, region: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4))
        #expect(early.red > early.green + 80 && late.green > late.red + 80)
        #expect(try await TestMedia.rms(of: out, from: 0.3, to: 1.7) > 0.1)
        #expect(try await TestMedia.rms(of: out, from: 2.3, to: 4.7) > 0.1)
    }

    @Test func recordingsOfDifferentSizesAreFittedIntoOnePicture() async throws {
        let wide = try await TestMedia.video(seconds: 2, color: (200, 20, 20), width: 320, height: 180)
        let small = try await TestMedia.video(seconds: 2, color: (20, 200, 20), width: 160, height: 90)
        let out = TestMedia.tempURL("mp4")
        try await TakeJoiner.join([wide, small], to: out)
        let track = try await AVURLAsset(url: out).loadTracks(withMediaType: .video)[0]
        let size = try await track.load(.naturalSize)
        #expect(size == CGSize(width: 320, height: 180), "the larger size wins: \(size)")
        let length = try await TestMedia.duration(of: out)
        #expect(abs(length - 4) < 0.3)
        // The smaller clip is scaled up to fill the picture, not left small in a corner.
        let second = try await TestMedia.channels(of: out, at: 3, region: CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9))
        #expect(second.green > second.red + 80, "scaled to fill: \(second)")
    }

    @Test func oneRecordingIsNotAJoin() async throws {
        let only = try await TestMedia.video(seconds: 1, color: (1, 1, 1))
        await #expect(throws: JoinError.self) { try await TakeJoiner.join([only], to: TestMedia.tempURL("mp4")) }
    }

    @Test func aFileWithNoPictureIsRefusedByName() async throws {
        let video = try await TestMedia.video(seconds: 1, color: (1, 1, 1))
        let sound = try TestMedia.tone(seconds: 1, frequency: 440)
        do {
            try await TakeJoiner.join([video, sound], to: TestMedia.tempURL("mp4"))
            Issue.record("a sound file has no video to join")
        } catch let error as JoinError {
            if case .noVideo = error {} else { Issue.record("wrong error \(error)") }
        }
    }
}

@Suite(.serialized) struct VideoImporterTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aNameIsTakenFromTheFileAndNeverClashes() throws {
        let library = try folder()
        defer { try? FileManager.default.removeItem(at: library) }
        let source = URL(fileURLWithPath: "/Users/x/Movies/Demo: v1/final.mov")
        #expect(VideoImporter.baseName(for: source, in: library) == "final")
        try Data([0]).write(to: TakeFiles(directory: library, baseName: "final").video)
        #expect(VideoImporter.baseName(for: source, in: library) == "final 2")
        #expect(VideoImporter.baseName(for: URL(fileURLWithPath: "/tmp/.hidden.mp4"), in: library) == "hidden")
        #expect(VideoImporter.baseName(for: URL(fileURLWithPath: "/tmp/a:b.mov"), in: library) == "a-b")
    }

    @Test func anMP4IsCopiedAndGetsNotesNamedAfterIt() async throws {
        let library = try folder()
        defer { try? FileManager.default.removeItem(at: library) }
        let video = try await TestMedia.video(seconds: 2, color: (10, 10, 200), toneHz: 440)
        let named = library.deletingLastPathComponent().appendingPathComponent("Quarterly demo-\(UUID().uuidString.prefix(4)).mp4")
        try FileManager.default.copyItem(at: video, to: named)
        defer { try? FileManager.default.removeItem(at: named) }

        let files = try await VideoImporter.importVideo(from: named, into: library)
        #expect(FileManager.default.fileExists(atPath: files.video.path))
        #expect(FileManager.default.fileExists(atPath: named.path), "the source stays where it was")
        let metadata = try #require(TakeLibrary.metadata(for: files))
        #expect(metadata.title.hasPrefix("Quarterly demo"))
        #expect(abs((metadata.durationSeconds ?? 0) - 2) < 0.2)
        let entries = TakeLibrary.load(directory: library)
        #expect(entries.count == 1 && entries[0].title.hasPrefix("Quarterly demo"))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: library.appendingPathComponent(".relaytake-processing").path)
        #expect(leftovers.isEmpty, "staging is cleaned up: \(leftovers)")
    }

    @Test func aMovIsConvertedToAnMP4() async throws {
        let library = try folder()
        defer { try? FileManager.default.removeItem(at: library) }
        let mp4 = try await TestMedia.video(seconds: 2, color: (10, 200, 10), toneHz: 440)
        let mov = TestMedia.tempURL("mov")
        let session = AVAssetExportSession(asset: AVURLAsset(url: mp4), presetName: AVAssetExportPresetPassthrough)!
        try await session.export(to: mov, as: .mov)
        defer { try? FileManager.default.removeItem(at: mov) }

        let files = try await VideoImporter.importVideo(from: mov, into: library)
        #expect(files.video.pathExtension == "mp4")
        #expect(abs(try await TestMedia.duration(of: files.video) - 2) < 0.2)
        let tracks = try await AVURLAsset(url: files.video).loadTracks(withMediaType: .audio)
        #expect(tracks.count == 1, "the sound comes along")
    }

    @Test func somethingThatIsNotAVideoIsRefusedAndLeavesNothing() async throws {
        let library = try folder()
        defer { try? FileManager.default.removeItem(at: library) }
        let text = library.deletingLastPathComponent().appendingPathComponent("notes-\(UUID().uuidString).mov")
        try Data("not a video".utf8).write(to: text)
        defer { try? FileManager.default.removeItem(at: text) }
        await #expect(throws: ImportError.self) { try await VideoImporter.importVideo(from: text, into: library) }
        let visible = try FileManager.default.contentsOfDirectory(atPath: library.path).filter { !$0.hasPrefix(".") }
        #expect(visible.isEmpty)
        // A sound file has no picture either.
        let tone = try TestMedia.tone(seconds: 1, frequency: 440)
        await #expect(throws: ImportError.self) { try await VideoImporter.importVideo(from: tone, into: library) }
    }
}

@Suite(.serialized) struct StillFrameTests {
    @Test func gifFramesCoverTheChosenStretchAndNeverPassTheEnd() {
        let times = GIFExporter.frameTimes(start: 2, length: 3, duration: 20, fps: 10)
        #expect(times.count == 30 && times.first == 2 && abs(times.last! - 4.9) < 1e-9)
        let clipped = GIFExporter.frameTimes(start: 18, length: 10, duration: 20, fps: 10)
        #expect(clipped.count == 20 && clipped.last! < 20)
        #expect(GIFExporter.frameTimes(start: 19.99, length: 5, duration: 20, fps: 10).isEmpty, "nothing left to show")
        #expect(GIFExporter.frameTimes(start: 0, length: 600, duration: 600, fps: 15).count == GIFExporter.maxFrames)
        #expect(GIFExporter.frameTimes(start: -5, length: 1, duration: 10, fps: 10).first == 0)
    }

    @Test func aGifIsWrittenWithTheRightFramesAndSize() async throws {
        let source = try await TestMedia.video(seconds: 3, color: (200, 60, 20))
        let out = TestMedia.tempURL("gif")
        defer { try? FileManager.default.removeItem(at: out) }
        try await GIFExporter.export(asset: AVURLAsset(url: source), start: 0.5, length: 2, fps: 10, maxWidth: 160, to: out)
        let data = try Data(contentsOf: out)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "GIF8", "a GIF signature (ImageIO writes 87a or 89a)")
        let image = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetCount(image) == 20)
        let frame = try #require(CGImageSourceCreateImageAtIndex(image, 0, nil))
        #expect(frame.width == 160 && frame.height == 90, "scaled down from 320×180: \(frame.width)×\(frame.height)")
        // No half-written file is left in the folder.
        let neighbours = try FileManager.default.contentsOfDirectory(atPath: out.deletingLastPathComponent().path).filter { $0.hasPrefix(".relaytake-") && $0.hasSuffix(".gif") }
        #expect(neighbours.isEmpty)
    }

    @Test func aGifPastTheEndOfTheVideoIsRefusedWithAReason() async throws {
        let source = try await TestMedia.video(seconds: 1, color: (1, 1, 1))
        let out = TestMedia.tempURL("gif")
        await #expect(throws: GIFExporter.GIFError.self) {
            try await GIFExporter.export(asset: AVURLAsset(url: source), start: 5, length: 3, fps: 10, maxWidth: 160, to: out)
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func eachClickGetsOneMomentAndDoubleClicksCountOnce() {
        let clicks = [3, 1, 1.4, 7.2, 30].map { ClickEvent(time: $0, x: 0.5, y: 0.5) }
        #expect(ClickFrames.moments(clicks: clicks, duration: 10) == [1, 3, 7.2], "sorted, 1.4 is a double click, 30 is past the end")
        #expect(ClickFrames.moments(clicks: [], duration: 10).isEmpty)
        #expect(ClickFrames.moments(clicks: [ClickEvent(time: -1, x: 0, y: 0)], duration: 10).isEmpty)
    }

    @Test func clickFramesAreNumberedToSortAndNameTheirMoment() {
        #expect(ClickFrames.fileName(number: 3, of: 12, time: 72.9) == "Click 03 at 1m12s.png")
        #expect(ClickFrames.fileName(number: 7, of: 120, time: 5) == "Click 007 at 0m05s.png")
        #expect(ClickFrames.folderName(for: "Q4: demo/final") == "Q4- demo-final – click frames")
        #expect(ClickFrames.folderName(for: "  ") == "Recording – click frames")
    }

    @Test func aPictureIsSavedAtEachClickMoment() async throws {
        // Red for the first second, then green.
        let red = try await TestMedia.video(seconds: 1, color: (230, 20, 20))
        let green = try await TestMedia.video(seconds: 2, color: (20, 230, 20))
        let source = TestMedia.tempURL("mp4")
        try await TakeJoiner.join([red, green], to: source)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("frames-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }

        let times = ClickFrames.moments(clicks: [ClickEvent(time: 0.4, x: 0.5, y: 0.5), ClickEvent(time: 2.2, x: 0.5, y: 0.5)], duration: 3)
        let files = try await ClickFrames.export(asset: AVURLAsset(url: source), times: times, to: folder)
        #expect(files.map(\.lastPathComponent) == ["Click 01 at 0m00s.png", "Click 02 at 0m02s.png"])
        func average(_ url: URL) throws -> (r: Double, g: Double) {
            let data = try Data(contentsOf: url)
            let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
            let region = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
            let brightnessRed = TestMedia.brightness(of: image, region: region)
            return (brightnessRed, 0)
        }
        // Both frames are real pictures of different colours: their brightness differs between red and green.
        let first = try average(files[0]).r, second = try average(files[1]).r
        #expect(abs(first - second) > 15, "a red frame and a green frame: \(first) vs \(second)")
    }

    @Test func aClickPastTheLastFrameStillGetsAPicture() async throws {
        let source = try await TestMedia.video(seconds: 2, color: (1, 1, 200))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("frames-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = try await ClickFrames.export(asset: AVURLAsset(url: source), times: [2.0], to: folder)
        #expect(files.count == 1 && FileManager.default.fileExists(atPath: files[0].path))
    }
}

@Suite(.serialized) struct CameraOnlyMixerTests {
    @Test func theSoundIsPlacedAfterThePictureBeganByTheDelayGiven() async throws {
        let picture = try await TestMedia.video(seconds: 4, color: (40, 40, 160))
        let sound = try TestMedia.tone(seconds: 3, frequency: 440, amplitude: 0.5)
        let out = TestMedia.tempURL("mp4")
        try await CameraOnlyMixer.merge(video: picture, audio: sound, audioDelay: 1, to: out)
        let length = try await TestMedia.duration(of: out)
        #expect(abs(length - 4) < 0.3, "the picture sets the length: \(length)")
        #expect(try await TestMedia.rms(of: out, from: 0.1, to: 0.8) < 0.02, "silent until the microphone began")
        #expect(try await TestMedia.rms(of: out, from: 1.4, to: 3.5) > 0.1, "then the sound")
    }

    @Test func soundThatBeganFirstHasItsHeadTrimmedSoItStillLinesUp() async throws {
        let picture = try await TestMedia.video(seconds: 3, color: (40, 160, 40))
        // A tone that is silent-free throughout is fine: what matters is it is cut to the picture's length.
        let sound = try TestMedia.tone(seconds: 5, frequency: 440)
        let out = TestMedia.tempURL("mp4")
        try await CameraOnlyMixer.merge(video: picture, audio: sound, audioDelay: -1.5, to: out)
        let length = try await TestMedia.duration(of: out)
        #expect(abs(length - 3) < 0.3)
        #expect(try await TestMedia.rms(of: out, from: 0.1, to: 2.8) > 0.1, "the sound fills the picture from the start")
    }

    @Test func aTakeWithNoSoundIsStillAVideo() async throws {
        let picture = try await TestMedia.video(seconds: 2, color: (40, 40, 160))
        let out = TestMedia.tempURL("mp4")
        try await CameraOnlyMixer.merge(video: picture, audio: nil, audioDelay: 0, to: out)
        #expect(abs(try await TestMedia.duration(of: out) - 2) < 0.3)
        #expect(try await AVURLAsset(url: out).loadTracks(withMediaType: .audio).isEmpty)
    }

    @Test func noPictureIsRefused() async throws {
        let sound = try TestMedia.tone(seconds: 1, frequency: 440)
        await #expect(throws: CameraOnlyMixer.MixError.self) {
            try await CameraOnlyMixer.merge(video: sound, audio: nil, audioDelay: 0, to: TestMedia.tempURL("mp4"))
        }
    }
}

@Suite struct JoinedClicksTests {
    @Test func eachRecordingsClicksMoveLaterByWhatCameBeforeIt() {
        let first = [ClickEvent(time: 1, x: 0.1, y: 0.1), ClickEvent(time: 9.5, x: 0.2, y: 0.2)]
        let second = [ClickEvent(time: 0.5, x: 0.9, y: 0.9), ClickEvent(time: 50, x: 0.5, y: 0.5)]
        let merged = JoinPlan.mergedClicks([(first, 10), (second, 4)])
        #expect(merged.map(\.time) == [1, 9.5, 10.5], "a click past the end of its clip is dropped")
        #expect(merged[2].x == 0.9)
        #expect(JoinPlan.mergedClicks([]).isEmpty)
    }
}
