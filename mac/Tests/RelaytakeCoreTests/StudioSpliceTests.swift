import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct SpliceCutTests {
    @Test func splicingBreaksTheVideoWithoutRemovingAnything() {
        var cuts = EditModel(duration: 10)
        let r1 = cuts.splice(atOutput: 4)
        #expect(r1)
        #expect(cuts.partSpans == [TimeSpan(start: 0, end: 4), TimeSpan(start: 4, end: 10)])
        #expect(cuts.keptDuration == 10)
        #expect(cuts.isSplice(afterPart: 0))
        let r2 = cuts.splice(atOutput: 7)
        #expect(r2)
        #expect(cuts.partSpans.count == 3 && cuts.keptDuration == 10)
    }

    @Test func aSpliceTooCloseToAnEdgeIsRefused() {
        var cuts = EditModel(duration: 10)
        let r3 = cuts.splice(atOutput: 0.05)
        #expect(!r3)
        let r4 = cuts.splice(atOutput: 9.95)
        #expect(!r4)
        #expect(cuts.segments.count == 1)
        cuts.splice(atOutput: 5)
        let r101 = cuts.splice(atOutput: 5.1)
        #expect(!r101)  // would leave a sliver beside the existing splice
    }

    @Test func removingAPartLeavesAGapNotASplice() throws {
        var cuts = EditModel(duration: 10)
        cuts.splice(atOutput: 3)
        cuts.splice(atOutput: 7)
        try cuts.remove(cuts.partSpans[1])  // the middle part
        #expect(cuts.keptDuration == 6)
        #expect(cuts.segments == [TimeSpan(start: 0, end: 3), TimeSpan(start: 7, end: 10)])
        #expect(!cuts.isSplice(afterPart: 0))
    }

    @Test func aSpliceCanBeUndoneAndSlid() {
        var cuts = EditModel(duration: 10)
        cuts.splice(atOutput: 4)
        let r5 = cuts.slideSplice(afterPart: 0, toSource: 6)
        #expect(r5 == 6)
        #expect(cuts.partSpans == [TimeSpan(start: 0, end: 6), TimeSpan(start: 6, end: 10)])
        #expect(cuts.keptDuration == 10)
        let r102 = cuts.slideSplice(afterPart: 0, toSource: 99)
        #expect(r102 == 10 - EditModel.minimumPart)  // never empties a part
        let r6 = cuts.removeSplice(afterPart: 0)
        #expect(r6)
        #expect(cuts.segments == [TimeSpan(start: 0, end: 10)])
        let r7 = cuts.removeSplice(afterPart: 0)
        #expect(!r7)
    }

    @Test func aGapIsNotASpliceSoItCannotBeSlidOrMerged() throws {
        var cuts = EditModel(duration: 10)
        try cuts.remove(TimeSpan(start: 4, end: 6))
        let r8 = cuts.slideSplice(afterPart: 0, toSource: 5)
        #expect(r8 == nil)
        let r9 = cuts.removeSplice(afterPart: 0)
        #expect(!r9)
    }

    @Test func partIndexFindsThePartUnderTheMoment() {
        var cuts = EditModel(duration: 10)
        cuts.splice(atOutput: 4)
        #expect(cuts.partIndex(atOutput: 1) == 0 && cuts.partIndex(atOutput: 4) == 1 && cuts.partIndex(atOutput: 10) == 1)
    }

    @Test func edgesStopAtTheirNeighborsAndTheEndsOfTheOriginal() throws {
        var cuts = EditModel(duration: 10)
        try cuts.remove(TimeSpan(start: 4, end: 6))  // parts 0–4 and 6–10
        // Pulling the left part's end out can only bring back what was removed.
        let grown = cuts.moveEdge(ofPart: 0, edge: .end, toSource: 9)
        #expect(cuts.segments[0].end == 6 && grown?.growth == 2)
        // The first part's start can go back to 0 and no further.
        var start = EditModel(duration: 10)
        start.moveEdge(ofPart: 0, edge: .start, toSource: 3)
        #expect(start.segments[0].start == 3)
        let back = start.moveEdge(ofPart: 0, edge: .start, toSource: -5)
        #expect(start.segments[0].start == 0 && back?.growth == 3)
    }
}

@Suite struct SpliceProjectTests {
    @Test func trimmingAnEdgeInPullsLaterThingsEarlierAndOutPushesThemLater() {
        var project = StudioProject(duration: 20)
        let text = project.addText(at: 10)
        project.updateText(text) { $0.start = 10; $0.end = 13 }
        let zoom = project.addZoom(at: 15)
        // Trim 2 s off the start of the video.
        project.moveEdge(ofPart: 0, edge: .start, toSource: 2)
        #expect(project.outputDuration == 18)
        #expect(abs(project.text(text)!.start - 8) < 1e-6)
        #expect(abs(project.zoom(zoom)!.start - 13) < 1e-6)
        // Bring it back: everything returns to where it was.
        project.moveEdge(ofPart: 0, edge: .start, toSource: 0)
        #expect(project.outputDuration == 20)
        #expect(abs(project.text(text)!.start - 10) < 1e-6)
        #expect(abs(project.zoom(zoom)!.start - 15) < 1e-6)
    }

    @Test func trimmingTheEndShortensWithoutMovingEarlierThings() {
        var project = StudioProject(duration: 20)
        let text = project.addText(at: 4)
        project.moveEdge(ofPart: 0, edge: .end, toSource: 12)
        #expect(project.outputDuration == 12)
        #expect(project.text(text)!.start == 4)
    }

    @Test func extendingBackIntoARemovedPartRestoresTheFootage() throws {
        var project = StudioProject(duration: 20)
        project.splice(at: 5)
        project.splice(at: 10)
        try project.remove(project.cuts.partSpans[1])  // gone: 5–10 of the original
        #expect(project.outputDuration == 15)
        project.moveEdge(ofPart: 0, edge: .end, toSource: 8)  // pull the first part's end back out
        #expect(project.outputDuration == 18)
        #expect(project.cuts.segments[0] == TimeSpan(start: 0, end: 8))
    }

    @Test func trimBeforeAndAfterWorkOnThePartUnderThePlayhead() {
        var project = StudioProject(duration: 20)
        project.splice(at: 10)  // parts 0–10 and 10–20
        let r103 = project.trimBefore(14)
        #expect(r103)  // drops 10–14
        #expect(project.cuts.segments == [TimeSpan(start: 0, end: 10), TimeSpan(start: 14, end: 20)])
        let r104 = project.trimAfter(12)
        #expect(r104)  // 12 is 2 s into the second part: drops 16–20
        #expect(project.cuts.segments == [TimeSpan(start: 0, end: 10), TimeSpan(start: 14, end: 16)])
        let r105 = project.trimBefore(0)
        #expect(!r105)  // nothing before the very start
    }

    @Test func splicingAloneCountsAsAnEditButChangesNothingYouCanSee() {
        var project = StudioProject(duration: 10)
        project.splice(at: 5)
        #expect(project.outputDuration == 10)
        #expect(project.isEdited)
    }
}

@Suite struct SplitItemTests {
    private func project() -> StudioProject { StudioProject(duration: 20) }

    @Test func splittingATextMakesTwoHalvesThatMeetAtTheSplit() {
        var project = project()
        let id = project.addText(at: 2, text: "Hello")
        let later = project.splitText(id, at: 3.5)
        #expect(later != nil && later != id)
        #expect(project.texts.count == 2)
        #expect(project.texts[0].end == 3.5 && project.texts[1].start == 3.5 && project.texts[1].end == 5)
        #expect(project.texts[1].text == "Hello" && project.texts[1].heightFraction == project.texts[0].heightFraction)
    }

    @Test func splittingAZoomKeepsFocusAndScaleAndRefusesSlivers() {
        var project = project()
        let id = project.addZoom(at: 2, scale: 2.5)
        project.updateZoom(id) { $0.x = 0.2; $0.y = 0.7; $0.end = $0.start + 4 }
        #expect(project.splitZoom(id, at: 2.3) == nil)  // first half would be too short
        #expect(project.splitZoom(id, at: 5.8) == nil)
        let later = project.splitZoom(id, at: 4)
        #expect(later != nil)
        #expect(project.zooms.map(\.start) == [2, 4] && project.zooms.map(\.end) == [4, 6])
        #expect(project.zooms.allSatisfy { $0.x == 0.2 && $0.y == 0.7 && $0.scale == 2.5 })
    }

    @Test func splittingAVoiceoverContinuesFromTheSamePlaceInTheFile() {
        var project = project()
        let url = URL(fileURLWithPath: "/tmp/take.m4a")
        let id = project.addVoiceover(url: url, name: "take", fileDuration: 8, start: 3)
        project.updateClip(id) { $0.fadeOut = 1 }
        let later = project.splitClip(id, at: 6)
        #expect(later != nil)
        #expect(project.clips[0].length == 3 && project.clips[0].fadeOut == 0)
        #expect(project.clips[1].start == 6 && project.clips[1].sourceStart == 3 && project.clips[1].length == 5)
        #expect(project.clips[1].fadeOut == 1)
        #expect(project.splitClip(id, at: 3.1) == nil)
    }

    @Test func splittingFittedMusicKeepsTheLaterHalfFittingTheVideoAndWrapsTheLoop() {
        var project = project()
        let url = URL(fileURLWithPath: "/tmp/song.m4a")
        let id = project.addMusic(url: url, name: "song", fileDuration: 5)
        let later = project.splitClip(id, at: 7)  // the 5 s song has looped once: 2 s into the second run
        #expect(later != nil)
        let first = project.clips[0], second = project.clips[1]
        #expect(first.length == 7 && !first.fitsVideo)
        #expect(second.fitsVideo && second.loops && abs(second.sourceStart - 2) < 0.001)
        #expect(project.clips[0].pieces(outputDuration: 20).map(\.length).reduce(0, +) == 7)
    }
}

@Suite struct OriginalAudioSpliceTests {
    @Test func theSoundFollowsTheVideoUntilItIsSplicedOnItsOwn() {
        var project = StudioProject(duration: 10)
        project.splice(at: 4)
        #expect(project.originalAudioFollowsVideo)
        #expect(project.originalAudioParts.map(\.source) == project.cuts.segments)

        let spliced = project.spliceOriginalAudio(at: 7)
        #expect(spliced)
        #expect(!project.originalAudioFollowsVideo)
        #expect(project.cuts.segments.count == 2)  // the video was not touched
        let parts = project.originalAudioParts
        #expect(parts.map(\.source) == [TimeSpan(start: 0, end: 4), TimeSpan(start: 4, end: 7), TimeSpan(start: 7, end: 10)])
        #expect(parts.map(\.start) == [0, 4, 7])
    }

    @Test func anAudioSpliceTooCloseToAnEdgeIsRefused() {
        var project = StudioProject(duration: 10)
        let refused = project.spliceOriginalAudio(at: 0.05)
        #expect(!refused)
        #expect(project.originalAudioFollowsVideo)
    }

    @Test func removingAnAudioPartLeavesSilenceAndKeepsTheVideo() {
        var project = StudioProject(duration: 10)
        project.spliceOriginalAudio(at: 3)
        project.spliceOriginalAudio(at: 6)
        let middle = project.originalAudioParts[1]
        let removed = project.removeOriginalAudioPart(middle.id)
        #expect(removed)
        #expect(project.outputDuration == 10)
        #expect(project.originalAudioParts.map(\.span) == [TimeSpan(start: 0, end: 3), TimeSpan(start: 6, end: 10)])
        project.relinkOriginalAudio()
        #expect(project.originalAudioParts.map(\.source) == [TimeSpan(start: 0, end: 10)])
    }

    @Test func cuttingTheVideoLaterRipplesTheSeparatelyCutSound() throws {
        var project = StudioProject(duration: 10)
        project.spliceOriginalAudio(at: 5)
        try project.remove(TimeSpan(start: 2, end: 4))
        // The first part lost its 2–4 s; the second moved 2 s earlier and still plays 5–10 s of the recording.
        let parts = project.originalAudioParts
        #expect(parts.count == 3)
        #expect(parts[0].source == TimeSpan(start: 0, end: 2) && parts[0].start == 0)
        #expect(parts[1].source == TimeSpan(start: 4, end: 5) && parts[1].start == 2)
        #expect(parts[2].source == TimeSpan(start: 5, end: 10) && parts[2].start == 3)
        #expect(parts[2].end == project.outputDuration)
    }

    @Test func separatelyCutSoundSurvivesTheDraft() throws {
        var project = StudioProject(duration: 10)
        project.spliceOriginalAudio(at: 5)
        let draft = StudioDraft(project: project, playhead: 0)
        let data = try JSONEncoder().encode(draft)
        let restored = try JSONDecoder().decode(StudioDraft.self, from: data).project(duration: 10, cameraSource: nil)
        #expect(restored?.audioParts == project.audioParts)
    }
}
