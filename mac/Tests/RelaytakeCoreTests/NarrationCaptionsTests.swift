import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct NarrationCaptionsTests {
    private let markers = [
        AgentMarker(name: "Open", time: 0), AgentMarker(name: "Wait", time: 10),
        AgentMarker(name: "Show", time: 20), AgentMarker(name: "End", time: 30),
    ]

    @Test func aLineSplitsIntoSentencesAndKeepsAnythingWithoutPunctuation() {
        #expect(NarrationCaptions.sentences(of: "Open it.  Then pick a take! Done?") == ["Open it.", "Then pick a take!", "Done?"])
        #expect(NarrationCaptions.sentences(of: "No full stop here") == ["No full stop here"])
        #expect(NarrationCaptions.sentences(of: "Version 1.5 is out. Nice.") == ["Version 1.5 is out.", "Nice."])
        #expect(NarrationCaptions.sentences(of: "  \n ").isEmpty)
    }

    @Test func sentencesShareTheirPartInProportionToTheirLength() {
        let beat = NarrationBeat(name: "Open", start: 10, end: 20, text: "Short. A much longer second sentence here.")
        let cues = NarrationCaptions.editedCues(beats: [beat])
        #expect(cues.map(\.text) == ["Short.", "A much longer second sentence here."])
        // A one-second lead and tail are 10% of a ten-second part, capped at 0.3 s.
        #expect(abs(cues[0].start - 10.3) < 1e-9)
        #expect(abs(cues[1].end - 19.7) < 1e-9)
        #expect(abs(cues[0].end - cues[1].start) < 1e-9)
        #expect(cues[0].end - cues[0].start < cues[1].end - cues[1].start)
    }

    @Test func aPartWithoutNarrationOrRoomMakesNoCaptions() {
        let beats = [
            NarrationBeat(name: "A", start: 0, end: 5, text: nil), NarrationBeat(name: "B", start: 5, end: 8, text: "  "),
            NarrationBeat(name: "C", start: 8, end: 8, text: "Nothing to fit."),
        ]
        #expect(NarrationCaptions.editedCues(beats: beats).isEmpty)
    }

    @Test func aVeryShortPartUsesAllOfItsTime() {
        let cues = NarrationCaptions.editedCues(beats: [NarrationBeat(name: "A", start: 2, end: 2.6, text: "Quick.")])
        #expect(cues == [CaptionSegment(start: 2, end: 2.6, text: "Quick.")])
    }

    @Test func narrationBecomesCaptionsOnTheEditedVideoAndCutsMoveThem() throws {
        let list = EditList(
            cuts: [.init(from: .marker("Wait"), to: .marker("Show"))],
            narration: ["Open": "Open the app.", "Show": "Here is the result.", "Wait": "This is cut."],
            narrationCaptions: true, captionStyle: "Bold", captionPosition: "top")
        let (project, outcome) = EditListApplier.apply(list, to: StudioProject(duration: 40), markers: markers, clicks: [])
        let captions = try #require(project.captions)
        #expect(captions.fromNarration == true)
        #expect(captions.style == .bold && captions.position == .top)
        // Cues are kept in the original's time, so the cut part (10–20 s) holds none.
        #expect(captions.cues.map(\.text) == ["Open the app.", "Here is the result."])
        #expect(captions.cues.allSatisfy { $0.end <= 10 || $0.start >= 20 })
        #expect(outcome.applied.contains { $0.hasPrefix("Narration became 2 caption lines") })
        #expect(outcome.warnings.isEmpty)

        // On the edited video the second line follows the first, ten seconds earlier than it was.
        let transcript = NarrationCaptions.transcript(for: project)
        #expect(transcript.map(\.text) == ["Open the app.", "Here is the result."])
        #expect(transcript[0].start >= 0 && transcript[0].end <= 10.0001)
        #expect(transcript[1].start >= 10 && transcript[1].end <= 20.0001)
        #expect(project.captionOverlays().count >= 2)
    }

    @Test func withoutNarrationOrWithAnUnknownStyleYouAreToldNotSilentlyIgnored() {
        let none = EditList(zooms: [.init(at: .seconds(2))], narrationCaptions: true)
        let (project, outcome) = EditListApplier.apply(none, to: StudioProject(duration: 40), markers: markers, clicks: [])
        #expect(project.captions == nil)
        #expect(outcome.warnings.contains { $0.contains("no narration line landed") })

        let odd = EditList(narration: ["Open": "Hello there."], narrationCaptions: true, captionStyle: "neon", captionPosition: "left")
        let (styled, notes) = EditListApplier.apply(odd, to: StudioProject(duration: 40), markers: markers, clicks: [])
        #expect(styled.captions?.style == .classic && styled.captions?.position == .bottom)
        #expect(notes.warnings.count == 2)
    }

    @Test func realCaptionsAreNotTreatedAsNarration() {
        var project = StudioProject(duration: 20)
        project.captions = StudioCaptions(cues: [CaptionSegment(start: 1, end: 3, text: "Spoken words")])
        #expect(NarrationCaptions.transcript(for: project).isEmpty)
    }

    @Test func savedDraftsWithoutTheNewFieldStillLoad() throws {
        let old = #"{"style":"classic","position":"bottom","cues":[{"start":1,"end":2,"text":"Hi"}]}"#
        let decoded = try JSONDecoder().decode(StudioCaptions.self, from: Data(old.utf8))
        #expect(decoded.fromNarration == nil)
        let narrated = StudioCaptions(cues: [], fromNarration: true)
        #expect(try JSONDecoder().decode(StudioCaptions.self, from: JSONEncoder().encode(narrated)).fromNarration == true)
    }

    @Test func theTranscriptBecomesAnOrdinaryCaptionsFile() {
        let lines = [CaptionSegment(start: 0.3, end: 3, text: "Open the app."), CaptionSegment(start: 3, end: 9.7, text: "Pick a take.")]
        let vtt = Captions.webVTT(lines)
        #expect(vtt.hasPrefix("WEBVTT"))
        #expect(vtt.contains("00:00:00.300 --> 00:00:03.000"))
        #expect(vtt.contains("Pick a take."))
    }

    @Test func theNewEditOptionsRoundTripThroughJSON() throws {
        let json = #"{"narration":{"A":"Hi."},"narrationCaptions":true,"captionStyle":"minimal","captionPosition":"middle"}"#
        let list = try JSONDecoder().decode(EditList.self, from: Data(json.utf8))
        #expect(list.narrationCaptions == true && list.captionStyle == "minimal" && list.captionPosition == "middle")
    }
}
