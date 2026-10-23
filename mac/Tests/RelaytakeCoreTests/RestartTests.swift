import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct RestartTests {
    private func lines(_ texts: [String], gap: Double = 0.5) -> [CaptionSegment] {
        var cursor = 0.0
        return texts.map { text in
            defer { cursor += 3 + gap }
            return CaptionSegment(start: cursor, end: cursor + 3, text: text)
        }
    }

    @Test func aSentenceSaidAgainFlagsTheFirstAttempt() {
        let segments = lines(["So today I want to show you the dashboard.", "So today I want to show you the dashboard.", "First, click Reports."])
        let found = RestartFinder.find(in: segments)
        #expect(found.count == 1)
        #expect(found.first?.span == TimeSpan(start: 0, end: 3))
        #expect(found.first?.kind == .restart)
    }

    @Test func aStartAbandonedThenSaidWholeIsFlagged() {
        let segments = lines(["So what I want to", "So what I want to show you is the new report.", "It has three tabs."])
        let found = RestartFinder.find(in: segments)
        #expect(found.map(\.span) == [TimeSpan(start: 0, end: 3)])
    }

    @Test func aSentenceSaidAgainWithAWordChangedIsFlagged() {
        let segments = lines(["Open the settings panel and click save.", "Open the settings window and click save."])
        #expect(RestartFinder.find(in: segments).count == 1)
    }

    @Test func differentSentencesAreNotFlagged() {
        let segments = lines(["Welcome to the quarterly review.", "Here is the revenue chart for this year.", "Notice the spike in March."])
        #expect(RestartFinder.find(in: segments).isEmpty)
    }

    @Test func shortLinesAreIgnored() {
        let segments = lines(["Okay.", "Okay.", "So now.", "So now we start."])
        #expect(RestartFinder.find(in: segments).isEmpty)
    }

    @Test func aRepeatLongAfterwardsIsNotARestart() {
        let segments = lines(["This is the same long sentence here.", "This is the same long sentence here."], gap: 20)
        #expect(RestartFinder.find(in: segments).isEmpty)
    }

    @Test func punctuationAndCapitalsDoNotMatter() {
        let segments = lines(["Click the Export button, then choose PDF!", "click the export button then choose pdf"])
        #expect(RestartFinder.find(in: segments).count == 1)
    }

    @Test func aModelSuggestionOverlappingARestartIsNotListedTwice() {
        let restart = EditSuggestion(kind: .restart, span: TimeSpan(start: 0, end: 3), reason: "again")
        let model = EditSuggestion(kind: .recommended, span: TimeSpan(start: 0, end: 3.2), reason: "repeat")
        let other = EditSuggestion(kind: .recommended, span: TimeSpan(start: 10, end: 12), reason: "other")
        let combined = EditSuggestions.combine(audioSilences: [], transcriptGaps: [], restarts: [restart], recommended: [model, other])
        #expect(combined.map(\.kind) == [.restart, .recommended])
        #expect(combined.last?.span.start == 10)
    }
}
