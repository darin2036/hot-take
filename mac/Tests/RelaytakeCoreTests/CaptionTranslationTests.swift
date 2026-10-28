import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct CaptionTranslationTests {
    private let lines = [
        CaptionSegment(start: 0, end: 2, text: "Hello there"),
        CaptionSegment(start: 2, end: 5, text: "this is a test"),
        CaptionSegment(start: 5, end: 6, text: "bye"),
    ]

    private func entry(_ files: TakeFiles) -> TakeEntry {
        TakeEntry(files: files, folder: "", created: Date(), title: "", summary: "", tags: [], hasCaptions: false)
    }

    private func takeFiles() throws -> (TakeFiles, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = TakeFiles(directory: root, baseName: "Take")
        try Data().write(to: files.video)
        return (files, root)
    }

    // MARK: Merging

    @Test func translatedTextKeepsEachLinesTiming() throws {
        let result = try CaptionTranslation.merge(lines, translated: [0: "Hola", 1: "esto es una prueba", 2: "adiós"])
        #expect(result.map(\.text) == ["Hola", "esto es una prueba", "adiós"])
        #expect(result.map(\.start) == [0, 2, 5])
        #expect(result.map(\.end) == [2, 5, 6])
    }

    @Test func aLineTheTranslatorLeftOutThrowsSoNothingHalfTranslatedIsSaved() {
        #expect(throws: CaptionTranslationError.missing(line: 1)) {
            try CaptionTranslation.merge(lines, translated: [0: "Hola", 2: "adiós"])
        }
        #expect(throws: CaptionTranslationError.missing(line: 0)) {
            try CaptionTranslation.merge(lines, translated: [0: "   \n ", 1: "x", 2: "y"])
        }
    }

    @Test func blankSourceLinesAreNotSentAndNotRequired() throws {
        let withBlank = [lines[0], CaptionSegment(start: 2, end: 3, text: "  "), lines[2]]
        #expect(CaptionTranslation.requests(for: withBlank).map(\.line) == [0, 2])
        let result = try CaptionTranslation.merge(withBlank, translated: [0: "Hola", 2: "adiós"])
        #expect(result.map(\.text) == ["Hola", "adiós"])
    }

    @Test func translatedLinesHaveTheirWhitespaceTidied() throws {
        let result = try CaptionTranslation.merge(lines, translated: [0: " Hola\n  amigo ", 1: "b", 2: "c"])
        #expect(result[0].text == "Hola amigo")
    }

    @Test func requestsCarryTheirLineNumberAndTidiedText() {
        let spaced = [CaptionSegment(start: 0, end: 1, text: "  one \n two ")]
        let requests = CaptionTranslation.requests(for: spaced)
        #expect(requests.count == 1)
        #expect(requests[0].line == 0)
        #expect(requests[0].text == "one two")
    }

    @Test func captionFileNameCarriesTheLanguageAndIsSafe() {
        #expect(CaptionTranslation.captionFileName(baseName: "Take", language: "es") == "Take.es.vtt")
        #expect(CaptionTranslation.captionFileName(baseName: "Take", language: "zh-Hans") == "Take.zh-Hans.vtt")
        #expect(CaptionTranslation.captionFileName(baseName: "Take", language: "a/b") == "Take.a-b.vtt")
    }

    // MARK: Saving with the take

    @Test func translationsRoundTripThroughTheNotesFile() throws {
        var metadata = TakeMetadata(title: "t", summary: "", created: Date(), transcript: lines)
        metadata.translations["es"] = [CaptionSegment(start: 0, end: 2, text: "Hola")]
        let decoded = try TakeMetadata.decode(metadata.encoded())
        #expect(decoded.translations == metadata.translations)
    }

    @Test func notesWrittenBeforeTranslationsExistStillOpen() throws {
        let old = #"{"title":"t","summary":"","created":"2026-01-01T00:00:00Z","transcript":[]}"#
        let decoded = try TakeMetadata.decode(Data(old.utf8))
        #expect(decoded.translations.isEmpty)
    }

    @Test func correctingTheTranscriptDropsTranslationsMadeFromTheOldWords() throws {
        let (files, root) = try takeFiles()
        defer { try? FileManager.default.removeItem(at: root) }
        let take = entry(files)
        try TakeLibrary.update(take) {
            $0.transcript = lines
            $0.translations["es"] = [CaptionSegment(start: 0, end: 2, text: "Hola")]
        }

        try TakeLibrary.saveTranscript(TranscriptEditing.apply(["Hello there", "this is a text", "bye"], to: lines), for: take)

        let saved = TakeLibrary.metadata(for: files)
        #expect(saved?.transcript.map(\.text) == ["Hello there", "this is a text", "bye"])
        #expect(saved?.translations.isEmpty == true)
    }

    @Test func savingATranslationKeepsTheTranscriptAndNotes() throws {
        let (files, root) = try takeFiles()
        defer { try? FileManager.default.removeItem(at: root) }
        let take = entry(files)
        try TakeLibrary.update(take) { $0.transcript = lines; $0.notes = "mine"; $0.tags = ["demo"] }

        let spanish = try CaptionTranslation.merge(lines, translated: [0: "Hola", 1: "una prueba", 2: "adiós"])
        try TakeLibrary.update(take) { $0.translations["es"] = spanish }

        let saved = TakeLibrary.metadata(for: files)
        #expect(saved?.transcript == lines)
        #expect(saved?.notes == "mine")
        #expect(saved?.tags == ["demo"])
        #expect(saved?.translations["es"] == spanish)
    }

    // MARK: Captions in other scripts

    @Test func aLongRunOfCJKTextWithoutSpacesIsCutIntoLines() {
        let text = String(repeating: "これはテストです", count: 12)  // 96 characters, no spaces
        let cues = Captions.cues(from: [CaptionSegment(start: 0, end: 12, text: text)], maxCharacters: 42)
        #expect(cues.count > 1)
        #expect(cues.allSatisfy { $0.text.count <= 42 })
        #expect(cues.map(\.text).joined() == text)
        #expect(cues.first?.start == 0)
        #expect(abs((cues.last?.end ?? 0) - 12) < 0.001)
    }

    @Test func aLongAsciiWordLikeAURLIsLeftWhole() {
        let url = "https://example.com/" + String(repeating: "a", count: 100)
        let cues = Captions.cues(from: [CaptionSegment(start: 0, end: 4, text: url)], maxCharacters: 42)
        #expect(cues.map(\.text) == [url])
    }

    // MARK: Studio captions

    @Test func studioCaptionsRecordTheirLanguageAndOlderDraftsStillOpen() throws {
        let captions = StudioCaptions(cues: lines, language: "es")
        let decoded = try JSONDecoder().decode(StudioCaptions.self, from: JSONEncoder().encode(captions))
        #expect(decoded.language == "es")

        let old = #"{"style":"classic","position":"bottom","cues":[{"start":0,"end":1,"text":"hi"}]}"#
        let opened = try JSONDecoder().decode(StudioCaptions.self, from: Data(old.utf8))
        #expect(opened.language == nil)
        #expect(opened.cues.map(\.text) == ["hi"])
    }
}
