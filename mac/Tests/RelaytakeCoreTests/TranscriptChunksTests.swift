import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct TranscriptChunksTests {
    @Test func shortTextStaysWhole() {
        #expect(TranscriptChunks.split("hello there") == ["hello there"])
        #expect(TranscriptChunks.split("   ").isEmpty)
    }

    @Test func longTextSplitsAtWordsAndKeepsEveryWord() {
        let words = (1...600).map { "word\($0)" }
        let pieces = TranscriptChunks.split(words.joined(separator: " "), maxCharacters: 500)
        #expect(pieces.count > 1)
        #expect(pieces.allSatisfy { $0.count <= 500 })
        #expect(pieces.joined(separator: " ").split(separator: " ").map(String.init) == words)
    }

    @Test func textWithoutSpacesIsSplitByLength() {
        let pieces = TranscriptChunks.split(String(repeating: "字", count: 2500), maxCharacters: 1000)
        #expect(pieces.map(\.count) == [1000, 1000, 500])
    }

    @Test func runsCoverEverySegmentOnce() {
        let segments = (0..<200).map { CaptionSegment(start: Double($0), end: Double($0) + 1, text: "line number \($0) of talk") }
        let runs = TranscriptChunks.runs(of: segments, maxCharacters: 400)
        #expect(runs.count > 1)
        #expect(runs.first?.lowerBound == 0 && runs.last?.upperBound == 200)
        #expect(zip(runs, runs.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound })
        #expect(TranscriptChunks.runs(of: [], maxCharacters: 400).isEmpty)
    }

    @Test func aSegmentLongerThanTheLimitStillMakesProgress() {
        let segments = [CaptionSegment(start: 0, end: 1, text: String(repeating: "x", count: 900))]
        #expect(TranscriptChunks.runs(of: segments, maxCharacters: 100) == [0..<1])
    }

    @Test func digestNumbersTheParts() {
        let digest = SummaryPrompt.digest(of: ["First.", "Second."])
        #expect(digest.contains("Part 1: First.") && digest.contains("Part 2: Second."))
    }

    @Test func mergesAgentRequestsAndNotes() {
        let a = AgentBrief.Request(goal: "Fix login", steps: ["Open it", "Click Save"])
        let b = AgentBrief.Request(goal: "", steps: ["Check the toast"])
        let combined = AgentPrompt.combined([b, a])
        #expect(combined?.goal == "Fix login")
        #expect(combined?.steps == ["Check the toast", "Open it", "Click Save"])
        #expect(AgentPrompt.mergeText([a]).contains("Part 1 of the recording. Goal: Fix login"))
        #expect(AgentPrompt.combined([]) == nil)
        #expect(MetadataPrompt.mergeNotes(["- Email Sam\n- Ship it", "- email sam.\n- Update docs"]) == "- Email Sam\n- Ship it\n- Update docs")
    }
}
