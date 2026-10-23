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
