import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct CaptionTests {
    @Test func formatsTimestamps() {
        #expect(Captions.timestamp(0, millisecondSeparator: ".") == "00:00:00.000")
        #expect(Captions.timestamp(3725.5, millisecondSeparator: ",") == "01:02:05,500")
        #expect(Captions.timestamp(-4, millisecondSeparator: ".") == "00:00:00.000")
    }

    @Test func splitsLongSegmentsAndKeepsTotalTime() {
        let text = Array(repeating: "word", count: 40).joined(separator: " ")
        let cues = Captions.cues(from: [CaptionSegment(start: 10, end: 20, text: text)], maxCharacters: 50)
        #expect(cues.count > 1)
        #expect(cues.allSatisfy { $0.text.count <= 50 })
        #expect(cues.first?.start == 10)
        #expect(abs((cues.last?.end ?? 0) - 20) < 0.001)
        #expect(zip(cues, cues.dropFirst()).allSatisfy { abs($0.end - $1.start) < 0.001 })
    }

    @Test func writesWebVTTAndSRT() {
        let segments = [CaptionSegment(start: 1, end: 2.5, text: "Hello there"), .init(start: 3, end: 4, text: "  ")]
        #expect(Captions.webVTT(segments) == "WEBVTT\n\n00:00:01.000 --> 00:00:02.500\nHello there\n\n")
        #expect(Captions.srt(segments) == "1\n00:00:01,000 --> 00:00:02,500\nHello there\n\n")
    }
}

@Suite struct TakeTests {
    @Test func namesFilesWithoutColons() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_792_574_415)  // 2026-10-21 09:20:15 UTC
        let name = TakeFiles.baseName(for: date, calendar: calendar)
        #expect(name == "Hot Take 2026-10-21 at 09.20.15")
        let files = TakeFiles(directory: URL(fileURLWithPath: "/tmp/x"), baseName: name)
        #expect(files.video.lastPathComponent == "\(name).mp4")
        #expect(files.captions.pathExtension == "vtt")
        #expect(files.metadata.pathExtension == "json")
    }

    @Test func existingRelaytakeFolderKeepsBeingUsedAfterTheRename() throws {
        let movies = FileManager.default.temporaryDirectory.appendingPathComponent("movies-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: movies) }
        try FileManager.default.createDirectory(at: movies, withIntermediateDirectories: true)
        #expect(TakeFiles.defaultDirectory(movies: movies).lastPathComponent == "Hot Take")  // a fresh Mac
        let legacy = movies.appendingPathComponent("Relaytake")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        #expect(TakeFiles.defaultDirectory(movies: movies).lastPathComponent == "Relaytake")  // recordings already there
        try FileManager.default.createDirectory(at: movies.appendingPathComponent("Hot Take"), withIntermediateDirectories: true)
        #expect(TakeFiles.defaultDirectory(movies: movies).lastPathComponent == "Hot Take")
    }

    @Test func metadataRoundTrips() throws {
        let original = TakeMetadata(
            title: "Demo", summary: "S", created: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 12, transcript: [.init(start: 0, end: 1, text: "Hi")])
        #expect(try TakeMetadata.decode(original.encoded()) == original)
    }
}

@Suite struct SummaryTests {
    @Test func parsesFormattedReply() {
        let reply = "TITLE: \"Checkout bug walkthrough.\"\nSUMMARY: The cart total is wrong.\nIt resets on refresh."
        let parsed = SummaryPrompt.parse(reply)
        #expect(parsed.title == "Checkout bug walkthrough")
        #expect(parsed.summary == "The cart total is wrong. It resets on refresh.")
    }

    @Test func fallsBackWhenFormatIgnored() {
        let parsed = SummaryPrompt.parse("Just a plain paragraph.")
        #expect(parsed.title.isEmpty)
        #expect(parsed.summary == "Just a plain paragraph.")
    }

    @Test func clipsLongTranscriptsKeepingBothEnds() {
        let long = String(repeating: "a", count: 5000) + String(repeating: "b", count: 20000) + String(repeating: "c", count: 5000)
        let clipped = SummaryPrompt.clipped(long)
        #expect(clipped.count < long.count)
        #expect(clipped.hasPrefix("aaa") && clipped.hasSuffix("ccc"))
        #expect(clipped.contains("omitted"))
        #expect(SummaryPrompt.clipped("short") == "short")
    }
}
