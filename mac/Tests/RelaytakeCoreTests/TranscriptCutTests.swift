import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct FillerWordTests {
    /// Words laid end to end, the way SpeechTranscriber times them (each word's time runs into the next).
    private func words(_ timed: [(String, Double, Double)]) -> [TimedWord] {
        timed.map { TimedWord(text: $0.0, start: $0.1, end: $0.2) }
    }

    @Test func fillerSoundsAreFoundWithTheirTiming() {
        let heard = words([("So,", 0, 0.54), ("um,", 0.54, 1.08), ("today", 1.08, 1.44), ("I", 1.44, 1.74)])
        let found = FillerWords.find(in: heard)
        #expect(found.count == 1)
        #expect(found.first?.kind == .filler)
        #expect(abs((found.first?.span.start ?? 0) - 0.56) < 1e-9)
        #expect(abs((found.first?.span.end ?? 0) - 1.06) < 1e-9)
        #expect(found.first?.reason == "Filler: \u{201C}um\u{201D}")
    }

    @Test func fillersInARowBecomeOneCut() {
        let heard = words([("and", 0, 0.3), ("um,", 0.3, 0.7), ("uh,", 0.7, 1.1), ("then", 1.1, 1.4)])
        let found = FillerWords.find(in: heard)
        #expect(found.count == 1)
        #expect(found.first?.reason == "Filler: \u{201C}um, uh\u{201D}")
    }

    @Test func casePunctuationAndAhCount() {
        #expect(FillerWords.isFiller("Um,"))
        #expect(FillerWords.isFiller("UH."))
        #expect(FillerWords.isFiller("ah,"))  // how SpeechTranscriber writes some "uh"s
        #expect(FillerWords.isFiller("hmm…"))
    }

    @Test func realWordsAreLeftAlone() {
        for word in ["like", "so", "you", "know", "umbrella", "her", "a", "I"] { #expect(!FillerWords.isFiller(word)) }
        let heard = words([("I", 0, 0.2), ("like", 0.2, 0.5), ("umbrellas.", 0.5, 1.2)])
        #expect(FillerWords.find(in: heard).isEmpty)
    }

    @Test func aCutNeverReachesIntoTheWordsBeside() {
        // Overlapping times from the recognizer: the filler's time starts before the word before it ends.
        let heard = words([("So", 0, 0.6), ("uh", 0.5, 1.0), ("yes", 0.9, 1.3)])
        let span = FillerWords.find(in: heard).first?.span
        #expect((span?.start ?? 0) >= 0.6)
        #expect((span?.end ?? 2) <= 0.9)
    }

    @Test func aFillerTooShortToCutIsSkipped() {
        let heard = words([("so", 0, 0.5), ("uh", 0.5, 0.56), ("yes", 0.56, 1)])
        #expect(FillerWords.find(in: heard).isEmpty)
    }

    @Test func combineKeepsFillersButDropsOnesInsideARestart() {
        let restart = EditSuggestion(kind: .restart, span: TimeSpan(start: 0, end: 3), reason: "Said again")
        let inside = EditSuggestion(kind: .filler, span: TimeSpan(start: 1, end: 1.4), reason: "Filler: um")
        let outside = EditSuggestion(kind: .filler, span: TimeSpan(start: 5, end: 5.4), reason: "Filler: uh")
        let combined = EditSuggestions.combine(
            audioSilences: [], transcriptGaps: [], restarts: [restart], recommended: [], fillers: [inside, outside])
        #expect(combined.map(\.kind) == [.restart, .filler])
        #expect(combined.last?.span == outside.span)
    }

    @Test func savedWordsSurviveAndOldNotesDecodeWithout() throws {
        var metadata = TakeMetadata(title: "t", summary: "", created: Date(timeIntervalSince1970: 0))
        metadata.words = [TimedWord(text: "um,", start: 1, end: 1.5)]
        #expect(try TakeMetadata.decode(metadata.encoded()).words == metadata.words)
        let old = #"{"title":"t","summary":"","created":"1970-01-01T00:00:00Z","transcript":[]}"#
        #expect(try TakeMetadata.decode(Data(old.utf8)).words.isEmpty)
    }
}

@Suite struct TranscriptCutTests {
    private let lines = [
        CaptionSegment(start: 0, end: 4, text: "Welcome."),
        CaptionSegment(start: 4, end: 8, text: "This line was a mistake."),
        CaptionSegment(start: 8, end: 12, text: "Here is the report."),
    ]

    @Test func cuttingALineMarksItCutAndLeavesTheOthers() throws {
        var project = StudioProject(duration: 12)
        for span in TranscriptCuts.spans(of: [lines[1]]) {
            for output in project.cuts.outputSpans(forSource: span) { try project.remove(output) }
        }
        #expect(TranscriptCuts.state(of: lines[0], in: project.cuts) == .kept)
        #expect(TranscriptCuts.state(of: lines[1], in: project.cuts) == .cut)
        #expect(TranscriptCuts.state(of: lines[2], in: project.cuts) == .kept)
        #expect(abs(project.outputDuration - 8) < 1e-9)
    }

    @Test func aLineWithPartCutIsPartlyCut() throws {
        var project = StudioProject(duration: 12)
        try project.remove(TimeSpan(start: 5, end: 7))
        #expect(TranscriptCuts.state(of: lines[1], in: project.cuts) == .partlyCut)
    }

    @Test func neighbouringLinesJoinIntoOneSpan() {
        #expect(TranscriptCuts.spans(of: [lines[2], lines[0], lines[1]]) == [TimeSpan(start: 0, end: 12)])
        #expect(TranscriptCuts.spans(of: [lines[0], lines[2]]).count == 2)
    }

    @Test func theLinePlayingIsFoundFromTheOriginalTime() {
        #expect(TranscriptCuts.line(at: 5, in: lines) == 1)
        #expect(TranscriptCuts.line(at: 20, in: lines) == nil)
    }

    @Test func bringingBackALineRestoresTheOriginalEdit() throws {
        var project = StudioProject(duration: 12)
        try project.remove(TimeSpan(start: 4, end: 8))
        let restored = project.restore(source: TimeSpan(start: 4, end: 8))
        #expect(restored)
        #expect(project.cuts.segments == [TimeSpan(start: 0, end: 12)])
        let again = project.restore(source: TimeSpan(start: 4, end: 8))
        #expect(!again)  // nothing left to bring back
    }

    @Test func bringingBackMovesLaterTextToStayWithItsPicture() throws {
        var project = StudioProject(duration: 12)
        let id = project.addText(at: 9)  // over "Here is the report."
        try project.remove(TimeSpan(start: 4, end: 8))
        #expect(abs((project.text(id)?.start ?? 0) - 5) < 1e-9)
        project.restore(source: TimeSpan(start: 4, end: 8))
        #expect(abs((project.text(id)?.start ?? 0) - 9) < 1e-9)
    }

    @Test func bringingBackOnlyFillsWhatWasCut() throws {
        var model = EditModel(duration: 20)
        try model.remove(TimeSpan(start: 2, end: 4))
        try model.remove(TimeSpan(start: 6, end: 8))  // output 4–6 is source 8–10 now
        let pieces = model.restore(TimeSpan(start: 0, end: 20))
        #expect(pieces.count == 2)
        #expect(abs(pieces[0].at - 2) < 1e-9 && abs(pieces[0].length - 2) < 1e-9)
        #expect(abs(pieces[1].at - 6) < 1e-9 && abs(pieces[1].length - 2) < 1e-9)
        #expect(model.segments == [TimeSpan(start: 0, end: 20)])
    }

    @Test func bringingBackKeepsASpliceTheUserMade() throws {
        var model = EditModel(duration: 20)
        let spliced = model.splice(atOutput: 10)
        #expect(spliced)
        try model.remove(TimeSpan(start: 2, end: 4))
        model.restore(TimeSpan(start: 2, end: 4))
        #expect(model.segments == [TimeSpan(start: 0, end: 10), TimeSpan(start: 10, end: 20)])
    }
}
