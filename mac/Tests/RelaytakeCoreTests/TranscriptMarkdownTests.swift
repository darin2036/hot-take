import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct TranscriptMarkdownTests {
    @Test func theFileHasSummaryChaptersAndTimedLines() {
        let text = TranscriptMarkdown.markdown(
            title: "Demo", created: Date(timeIntervalSince1970: 0), duration: 75, summary: " A short demo. ", tags: ["a", "b"],
            transcript: [
                CaptionSegment(start: 0, end: 2, text: "Hello."), CaptionSegment(start: 12, end: 14, text: "Now the settings."),
                CaptionSegment(start: 20, end: 21, text: "  ")],
            chapters: [Chapter(start: 10, title: "Settings"), Chapter(start: 0, title: "Intro")])
        #expect(text.hasPrefix("# Demo\n\n"))
        #expect(text.contains("1:15"))
        #expect(text.contains("Tags: a, b"))
        #expect(text.contains("## Summary\n\nA short demo.\n"))
        #expect(text.contains("### Intro\n\n**[0:00]** Hello.\n\n### Settings\n\n**[0:12]** Now the settings.\n"))
        #expect(!text.contains("0:20"))
    }

    @Test func aMissingTitleAndSummaryAreLeftOut() {
        let text = TranscriptMarkdown.markdown(
            title: "", created: Date(), duration: nil, summary: "", tags: [], transcript: [], chapters: [])
        #expect(text.hasPrefix("# Transcript\n"))
        #expect(!text.contains("## Summary"))
    }
}
