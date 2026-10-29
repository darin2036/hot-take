import AVFoundation
import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct ChapterTrackTests {
    /// The chapters a player reads from the file: each name with its start time.
    private func chapters(in url: URL) async throws -> [(start: Double, title: String)] {
        let asset = AVURLAsset(url: url)
        var found: [(start: Double, title: String)] = []
        for locale in try await asset.load(.availableChapterLocales) {
            for group in try await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [.commonKeyTitle]) {
                let title = try await group.items.first?.load(.stringValue) ?? ""
                found.append((group.timeRange.start.seconds, title))
            }
        }
        return found
    }

    /// Every compressed sample of a track, in order. Equal lists mean the pictures and sound were carried over intact.
    private func samples(of url: URL, _ type: AVMediaType) async throws -> [Data] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: type).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var result: [Data] = []
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var bytes = Data(count: length)
            _ = bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            result.append(bytes)
        }
        return result
    }

    private func duration(of url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    @Test func chaptersReadBackWithTheirNamesAndTimes() async throws {
        let source = try await TestMedia.video(seconds: 12, color: (200, 80, 40))
        let out = TestMedia.tempURL("mp4")
        try ChapterTrack.add(
            [Chapter(start: 0, title: "Setup"), Chapter(start: 4, title: "Café — billing"), Chapter(start: 8.5, title: "Wrap-up")],
            duration: 12, from: source, to: out)

        let found = try await chapters(in: out)
        #expect(found.map(\.title) == ["Setup", "Café — billing", "Wrap-up"])
        for (got, want) in zip(found.map(\.start), [0, 4, 8.5]) {
            #expect(abs(got - want) < 0.01)
        }
    }

    @Test func picturesAndSoundAreCarriedOverIntact() async throws {
        // Sound made by an export puts the movie header last; the silent writer below puts it first.
        for source in [try await TestMedia.video(seconds: 6, color: (10, 120, 200), toneHz: 440),
                       try await TestMedia.video(seconds: 6, color: (10, 120, 200), faststart: true),
                       try await TestMedia.video(seconds: 6, color: (10, 120, 200))] {
            let out = TestMedia.tempURL("mp4")
            try ChapterTrack.add([Chapter(start: 0, title: "A"), Chapter(start: 3, title: "B")], duration: 6, from: source, to: out)

            let pictures = try await (samples(of: out, .video), samples(of: source, .video))
            let sounds = try await (samples(of: out, .audio), samples(of: source, .audio))
            let lengths = try await (duration(of: out), duration(of: source))
            #expect(pictures.0 == pictures.1)
            #expect(sounds.0 == sounds.1)
            #expect(abs(lengths.0 - lengths.1) < 0.05)
            #expect(try await chapters(in: out).map(\.title) == ["A", "B"])
        }
    }

    @Test func aFirstChapterAfterTheStartGetsAnUntitledOpening() async throws {
        let source = try await TestMedia.video(seconds: 8, color: (90, 90, 90))
        let out = TestMedia.tempURL("mp4")
        try ChapterTrack.add([Chapter(start: 2, title: "Middle"), Chapter(start: 5, title: "End")], duration: 8, from: source, to: out)

        let found = try await chapters(in: out)
        #expect(found.contains { abs($0.start - 2) < 0.01 && $0.title == "Middle" })
        #expect(found.contains { abs($0.start - 5) < 0.01 && $0.title == "End" })
        let pictures = try await (samples(of: out, .video), samples(of: source, .video))
        #expect(pictures.0 == pictures.1)
    }

    @Test func chaptersPastTheEndAreLeftOut() async throws {
        let source = try await TestMedia.video(seconds: 6, color: (30, 30, 30))
        let out = TestMedia.tempURL("mp4")
        try ChapterTrack.add([Chapter(start: 0, title: "Kept"), Chapter(start: 20, title: "Dropped")], duration: 6, from: source, to: out)

        #expect(try await chapters(in: out).map(\.title) == ["Kept"])
    }

    @Test func withNoChaptersTheCopyIsUnchanged() async throws {
        let source = try await TestMedia.video(seconds: 4, color: (60, 60, 60))
        let out = TestMedia.tempURL("mp4")
        try ChapterTrack.add([], duration: 4, from: source, to: out)

        #expect(try await chapters(in: out).isEmpty)
        let pictures = try await (samples(of: out, .video), samples(of: source, .video))
        #expect(pictures.0 == pictures.1)
    }
}
