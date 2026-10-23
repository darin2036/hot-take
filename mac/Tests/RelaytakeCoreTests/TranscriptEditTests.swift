import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct TranscriptEditTests {
    private let lines = [
        CaptionSegment(start: 0, end: 2, text: "Hello there"),
        CaptionSegment(start: 2, end: 5, text: "this is a test"),
        CaptionSegment(start: 5, end: 6, text: "bye"),
    ]

    private func entry(_ files: TakeFiles) -> TakeEntry {
        TakeEntry(files: files, folder: "", created: Date(), title: "", summary: "", tags: [], hasCaptions: false)
    }

    @Test func editedTextKeepsTheLinesTiming() {
        let result = TranscriptEditing.apply(["Hello there", "this is a text", "bye"], to: lines)
        #expect(result.map(\.text) == ["Hello there", "this is a text", "bye"])
        #expect(result.map(\.start) == [0, 2, 5])
        #expect(result.map(\.end) == [2, 5, 6])
    }

    @Test func lineBreaksAndExtraSpacesBecomeSingleSpaces() {
        let result = TranscriptEditing.apply(["  Hello\n\nthere  ", "this   is", "bye"], to: lines)
        #expect(result[0].text == "Hello there")
        #expect(result[1].text == "this is")
    }

    @Test func aLineLeftEmptyIsDroppedAndTheOthersKeepTheirTiming() {
        let result = TranscriptEditing.apply(["Hello there", "   ", "bye"], to: lines)
        #expect(result.map(\.text) == ["Hello there", "bye"])
        #expect(result.map(\.start) == [0, 5])
    }

    @Test func missingEditsKeepTheOriginalText() {
        let result = TranscriptEditing.apply(["Changed"], to: lines)
        #expect(result.map(\.text) == ["Changed", "this is a test", "bye"])
    }

    @Test func savingRewritesTheMetadataAndTheCaptionsFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tx-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = TakeFiles(directory: root, baseName: "Take")
        try Data().write(to: files.video)
        try Captions.webVTT(lines).write(to: files.captions, atomically: true, encoding: .utf8)
        let entry = entry(files)

        let fixed = TranscriptEditing.apply(["Hello there", "this is a text", "bye"], to: lines)
        try TakeLibrary.saveTranscript(fixed, for: entry)

        #expect(TakeLibrary.metadata(for: files)?.transcript.map(\.text) == ["Hello there", "this is a text", "bye"])
        let vtt = try String(contentsOf: files.captions, encoding: .utf8)
        #expect(vtt.contains("this is a text"))
        #expect(!vtt.contains("this is a test"))
    }

    @Test func aTakeWithoutCaptionsDoesNotGainACaptionsFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tx-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = TakeFiles(directory: root, baseName: "Take")
        try Data().write(to: files.video)
        try TakeLibrary.saveTranscript(lines, for: entry(files))
        #expect(!FileManager.default.fileExists(atPath: files.captions.path))
        #expect(TakeLibrary.metadata(for: files)?.transcript == lines)
    }
}
