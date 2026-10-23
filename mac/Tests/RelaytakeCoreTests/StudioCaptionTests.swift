import AVFoundation
import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct StudioCaptionTests {
    private let cues = [
        CaptionSegment(start: 1, end: 3, text: "Hello there"),
        CaptionSegment(start: 4, end: 6, text: "Second line"),
        CaptionSegment(start: 8, end: 9, text: "Last"),
    ]

    @Test func captionsAreOffUntilTurnedOn() {
        var project = StudioProject(duration: 10)
        #expect(project.captionOverlays().isEmpty)
        #expect(!project.isEdited)
        project.captions = StudioCaptions(cues: cues)
        #expect(project.isEdited)
        #expect(project.captionOverlays().map(\.text) == ["Hello there", "Second line", "Last"])
    }

    @Test func aCutMovesLaterCaptionsAndDropsCutOnes() throws {
        var project = StudioProject(duration: 10)
        project.captions = StudioCaptions(cues: cues)
        try project.remove(TimeSpan(start: 3.5, end: 7))  // removes 3.5 s: "Second line" keeps only 0.5 s of its end at 6–7 cut
        let lines = project.captionOverlays()
        #expect(lines.map(\.text) == ["Hello there", "Last"])
        #expect(abs(lines[1].start - 4.5) < 0.001)  // 8 - 3.5
        #expect(lines.allSatisfy { !$0.fades })
    }

    @Test func aCaptionCutInHalfKeepsTheVisiblePart() throws {
        var project = StudioProject(duration: 10)
        project.captions = StudioCaptions(cues: [CaptionSegment(start: 2, end: 6, text: "A long sentence")])
        try project.remove(TimeSpan(start: 4, end: 5))
        let lines = project.captionOverlays()
        #expect(lines.count == 2)
        #expect(abs(lines[0].end - 4) < 0.001 && abs(lines[1].start - 4) < 0.001)
    }

    @Test func stylesAndPositionDecideLookAndPlace() {
        for style in CaptionStyle.allCases {
            var project = StudioProject(duration: 10)
            project.captions = StudioCaptions(style: style, position: .top, cues: cues)
            let line = project.captionOverlays()[0]
            #expect(line.y < 0.2)
            #expect(line.showsBackground == (style == .classic || style == .highlight))
        }
        var project = StudioProject(duration: 10)
        project.captions = StudioCaptions(position: .bottom, cues: cues)
        #expect(project.captionOverlays()[0].y > 0.8)
    }

    @Test func captionIdsStayTheSameBetweenCalls() {
        var project = StudioProject(duration: 10)
        project.captions = StudioCaptions(cues: cues)
        #expect(project.captionOverlays().map(\.id) == project.captionOverlays().map(\.id))
    }

    @Test func captionsAreBurnedIntoTheSavedVideoOnlyWhileSpoken() async throws {
        let source = try await TestMedia.video(seconds: 6, color: (20, 30, 120))
        var project = StudioProject(duration: 6)
        project.captions = StudioCaptions(style: .highlight, position: .bottom, cues: [CaptionSegment(start: 1, end: 3, text: "Caption on screen")])
        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: project, to: out) { _ in }
        let region = CGRect(x: 0.15, y: 0.75, width: 0.7, height: 0.2)
        let showing = try await TestMedia.brightness(of: out, at: 2, region: region)
        let after = try await TestMedia.brightness(of: out, at: 4.5, region: region)
        #expect(showing > after + 5, "a yellow box brightens the dark blue picture: \(showing) vs \(after)")
        let top = try await TestMedia.brightness(of: out, at: 2, region: CGRect(x: 0.15, y: 0.05, width: 0.7, height: 0.2))
        #expect(abs(top - after) < 10)
    }
}
