import AppKit
import Foundation
import Testing

@testable import RelaytakeCore

private let music = URL(fileURLWithPath: "/tmp/music.m4a")

@Suite struct StudioMappingTests {
    @Test func mapsOutputTimeBackToTheOriginal() throws {
        var model = EditModel(duration: 10)
        try model.remove(TimeSpan(start: 3, end: 6))  // output is 0–3 then original 6–10
        #expect(model.sourceTime(forOutput: 2) == 2)
        #expect(model.sourceTime(forOutput: 4) == 7)
        #expect(model.sourceTime(forOutput: 7.5) == nil)
        #expect(model.joins == [3])
        // An output range that crosses the cut maps to two pieces of the original.
        #expect(model.sourceSpans(forOutput: TimeSpan(start: 2, end: 5)) == [TimeSpan(start: 2, end: 3), TimeSpan(start: 6, end: 8)])
    }
}

@Suite struct StudioCutTests {
    @Test func removingAnOutputRangeRipplesTextAndShortensTheVideo() throws {
        var project = StudioProject(duration: 20)
        let before = project.addText(at: 1)  // 1–4
        project.updateText(before) { $0.end = 2.5 }
        let after = project.addText(at: 12)  // 12–15
        let across = project.addText(at: 4)  // 4–7
        try project.remove(TimeSpan(start: 5, end: 10))

        #expect(project.outputDuration == 15)
        #expect(project.text(before)?.start == 1 && project.text(before)?.end == 2.5)  // untouched
        #expect(project.text(after)?.start == 7 && project.text(after)?.end == 10)  // shifted left by 5
        #expect(project.text(across)?.start == 4 && project.text(across)?.end == 5)  // trimmed at the cut
    }

    @Test func textInsideTheRemovedRangeIsDropped() throws {
        var project = StudioProject(duration: 20)
        let inside = project.addText(at: 6)
        project.updateText(inside) { $0.end = 8 }
        try project.remove(TimeSpan(start: 5, end: 10))
        #expect(project.text(inside) == nil)
    }

    @Test func aVoiceoverCrossingACutIsSplitSoItStaysInSyncWithThePicture() throws {
        var project = StudioProject(duration: 20)
        let voice = project.addVoiceover(url: music, name: "Voiceover", fileDuration: 12, start: 2)  // plays 2–14
        try project.remove(TimeSpan(start: 6, end: 9))  // 3 s cut inside it

        let parts = project.clips.sorted { $0.start < $1.start }
        #expect(parts.count == 2)
        #expect(parts[0].id == voice && parts[0].start == 2 && parts[0].length == 4 && parts[0].sourceStart == 0)
        // The second part resumes at 7 s into the file (2 → 6 is 4 s, plus the 3 s that was cut) and starts at the cut.
        #expect(parts[1].start == 6 && parts[1].sourceStart == 7 && parts[1].length == 5)
    }

    @Test func aVoiceoverAfterTheCutShiftsLeftAndMusicThatFitsTheVideoIsUntouched() throws {
        var project = StudioProject(duration: 20)
        let voice = project.addVoiceover(url: music, name: "V", fileDuration: 4, start: 12)
        let bed = project.addMusic(url: music, name: "Song", fileDuration: 30)
        try project.remove(TimeSpan(start: 2, end: 6))
        #expect(project.clip(voice)?.start == 8)
        #expect(project.clip(bed)?.start == 0 && project.clip(bed)?.fitsVideo == true)
    }

    @Test func keepOnlyTrimsBothEndsAndRejectsEmpty() throws {
        var project = StudioProject(duration: 20)
        let text = project.addText(at: 8)
        try project.keepOnly(TimeSpan(start: 6, end: 14))
        #expect(project.outputDuration == 8)
        #expect(project.text(text)?.start == 2)  // 8 − 6
        #expect(throws: EditError.self) { try project.keepOnly(TimeSpan(start: 3, end: 3.01)) }
        #expect(project.outputDuration == 8)  // a rejected edit changes nothing
    }

    @Test func aRemovalThatFailsLeavesTheProjectUnchanged() {
        var project = StudioProject(duration: 5)
        let snapshot = project
        #expect(throws: EditError.self) { try project.remove(TimeSpan(start: 0, end: 5)) }
        #expect(project == snapshot)
    }
}

@Suite struct StudioTextTests {
    @Test func newTextStartsAtThePlayheadAndStaysInsideTheVideo() {
        var project = StudioProject(duration: 10)
        let a = project.addText(at: 4)
        #expect(project.text(a)?.start == 4 && project.text(a)?.end == 7)
        let b = project.addText(at: 9.9)  // near the end: still has room to be seen
        #expect((project.text(b)?.length ?? 0) >= StudioProject.minimumLength)
        #expect((project.text(b)?.end ?? 99) <= 10)
    }

    @Test func editsAreClamped() {
        var project = StudioProject(duration: 10)
        let id = project.addText(at: 2)
        project.updateText(id) { $0.x = 4; $0.y = -1; $0.end = 99 }
        #expect(project.text(id)?.x == 1 && project.text(id)?.y == 0 && project.text(id)?.end == 10)
        project.moveText(id, to: 9)  // keeps its length, stops at the end
        #expect(project.text(id)?.end == 10)
        #expect(abs((project.text(id)?.start ?? 0) - 2) < 0.001)  // length was 8, so it must start at 2
    }
}

@Suite struct StudioAudioTests {
    @Test func musicFitsTheVideoAndLoopsWhenShort() {
        var project = StudioProject(duration: 10)
        let id = project.addMusic(url: music, name: "Song", fileDuration: 4)
        let clip = project.clip(id)!
        let pieces = clip.pieces(outputDuration: project.outputDuration)
        #expect(pieces.map(\.outputStart) == [0, 4, 8])
        #expect(pieces.map(\.length) == [4, 4, 2])
        #expect(pieces.allSatisfy { $0.sourceStart == 0 })
    }

    @Test func musicLongerThanTheVideoIsCutAtTheEnd() {
        var project = StudioProject(duration: 6)
        let id = project.addMusic(url: music, name: "Song", fileDuration: 90)
        let clip = project.clip(id)!
        #expect(clip.pieces(outputDuration: 6) == [AudioClip.Piece(outputStart: 0, sourceStart: 0, length: 6)])
    }

    @Test func aClipThatDoesNotLoopPlaysOnceAndAResumedClipStartsMidFile() {
        let once = AudioClip(kind: .voiceover, url: music, name: "V", sourceDuration: 3, start: 2, length: 3)
        #expect(once.pieces(outputDuration: 20) == [AudioClip.Piece(outputStart: 2, sourceStart: 0, length: 3)])
        let resumed = AudioClip(kind: .voiceover, url: music, name: "V", sourceDuration: 10, sourceStart: 7, start: 6, length: 3)
        #expect(resumed.pieces(outputDuration: 20) == [AudioClip.Piece(outputStart: 6, sourceStart: 7, length: 3)])
        #expect(once.pieces(outputDuration: 3).first?.length == 1)  // the video ends before the clip does
        #expect(once.pieces(outputDuration: 1).isEmpty)  // starts after the video ends
    }

    @Test func fadesBecomeRampsAndNeverOverlap() {
        let clip = AudioClip(kind: .music, url: music, name: "S", sourceDuration: 60, length: 10, volume: 0.5, fadeIn: 1, fadeOut: 2)
        #expect(clip.ramps(outputDuration: 10) == [
            AudioClip.Ramp(start: 0, end: 1, from: 0, to: 0.5), AudioClip.Ramp(start: 8, end: 10, from: 0.5, to: 0),
        ])
        let short = AudioClip(kind: .music, url: music, name: "S", sourceDuration: 60, length: 2, fadeIn: 5, fadeOut: 5)
        let ramps = short.ramps(outputDuration: 2)
        #expect(ramps.count == 2 && ramps[0].end <= ramps[1].start)  // each fade is at most half the clip
    }

    @Test func clipEditsAreClamped() {
        var project = StudioProject(duration: 10)
        let id = project.addVoiceover(url: music, name: "V", fileDuration: 3, start: 1)
        project.updateClip(id) { $0.volume = 9; $0.start = 50; $0.length = 99 }
        let clip = project.clip(id)!
        #expect(clip.volume == 1.5 && clip.start <= 9.9 && clip.length <= 3)
    }
}

@Suite struct UndoStackTests {
    @Test func undoAndRedoWalkThroughSnapshots() {
        var stack = UndoStack<Int>()
        var value = 1
        stack.record(value); value = 2
        stack.record(value); value = 3
        #expect(stack.canUndo && !stack.canRedo)
        value = stack.undo(current: value)!  // 2
        value = stack.undo(current: value)!  // 1
        #expect(value == 1 && !stack.canUndo && stack.canRedo)
        value = stack.redo(current: value)!  // 2
        #expect(value == 2)
        stack.record(value); value = 9  // a new edit discards the redo history
        #expect(!stack.canRedo)
        #expect(stack.undo(current: value) == 2)
    }

    @Test func projectIsEditedOnlyAfterAChange() throws {
        var project = StudioProject(duration: 10)
        #expect(!project.isEdited)
        project.originalVolume = 0.5
        #expect(project.isEdited)
        project.originalVolume = 1
        #expect(!project.isEdited)
        try project.remove(TimeSpan(start: 1, end: 2))
        #expect(project.isEdited)
    }
}

@Suite struct StudioRulesTests {
    @Test func aNewSongReplacesTheOldOne() {
        var project = StudioProject(duration: 10)
        project.addMusic(url: music, name: "A", fileDuration: 30)
        let second = project.addMusic(url: music, name: "B", fileDuration: 30)
        #expect(project.clips.count == 1 && project.clips.first?.id == second)
    }

    @Test func aNewVoiceoverReplacesOnlyWhatItOverlaps() {
        var project = StudioProject(duration: 30)
        let early = project.addVoiceover(url: music, name: "1", fileDuration: 4, start: 0)    // 0–4
        let middle = project.addVoiceover(url: music, name: "2", fileDuration: 4, start: 10)  // 10–14
        let redo = project.addVoiceover(url: music, name: "3", fileDuration: 6, start: 12)    // 12–18 overlaps "2"
        #expect(Set(project.clips.map(\.id)) == [early, redo])
        #expect(project.clip(middle) == nil)
    }

    @Test func overlappingTextGetsSeparateLanes() {
        var project = StudioProject(duration: 20)
        let a = project.addText(at: 0)   // 0–3
        let b = project.addText(at: 1)   // 1–4 overlaps a
        let c = project.addText(at: 3.5) // 3.5–6.5 fits back in lane 0 after a
        let lanes = project.textLanes()
        #expect(lanes[a] == 0 && lanes[b] == 1 && lanes[c] == 0)
    }

    @Test func mapsAPartOfTheOriginalOntoTheEditedTimeline() throws {
        var model = EditModel(duration: 10)
        try model.remove(TimeSpan(start: 3, end: 6))  // edited video: original 0–3 then 6–10
        #expect(model.outputSpans(forSource: TimeSpan(start: 2, end: 8)) == [TimeSpan(start: 2, end: 3), TimeSpan(start: 3, end: 5)])
        #expect(model.outputSpans(forSource: TimeSpan(start: 3.5, end: 5.5)).isEmpty)  // entirely cut out already
        #expect(model.outputSpans(forSource: TimeSpan(start: 7, end: 9)) == [TimeSpan(start: 4, end: 6)])
    }
}

@Suite struct TextStyleTests {
    @Test func fontsResolveWithTheRequestedTraits() {
        var text = TextOverlay(text: "x", start: 0, end: 1)
        let manager = NSFontManager.shared
        #expect(manager.traits(of: text.nsFont(pointSize: 40)).contains(.boldFontMask))  // bold system font by default
        text.isBold = false
        #expect(!manager.traits(of: text.nsFont(pointSize: 40)).contains(.boldFontMask))
        text.isItalic = true
        #expect(manager.traits(of: text.nsFont(pointSize: 40)).contains(.italicFontMask))

        if TextOverlay.fontFamilies.contains("Georgia") {
            text = TextOverlay(text: "x", start: 0, end: 1, fontFamily: "Georgia", isBold: true, isItalic: true)
            let font = text.nsFont(pointSize: 40)
            #expect(font.familyName == "Georgia")
            #expect(manager.traits(of: font).isSuperset(of: [.boldFontMask, .italicFontMask]))
        }
        #expect(abs(text.nsFont(pointSize: 40).pointSize - 40) < 0.01)
    }

    @Test func anUnknownFontFallsBackInsteadOfFailing() {
        let text = TextOverlay(text: "x", start: 0, end: 1, fontFamily: "No Such Font")
        #expect(text.nsFont(pointSize: 30).pointSize == 30)
    }

    @Test func theFontListStartsWithTheSystemFontAndOnlyHasInstalledFamilies() {
        let families = TextOverlay.fontFamilies
        #expect(families.first == TextOverlay.systemFont)
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        #expect(families.dropFirst().allSatisfy(installed.contains))
        #expect(families.count >= 3)
    }

    @Test func colorsAreClampedAndSurviveAConversion() {
        let odd = TextColor(red: 2, green: -1, blue: 0.5)
        #expect(odd.red == 1 && odd.green == 0 && odd.blue == 0.5)
        let round = TextColor(TextColor(red: 0.2, green: 0.6, blue: 0.9).nsColor)
        #expect(abs(round.red - 0.2) < 0.01 && abs(round.green - 0.6) < 0.01 && abs(round.blue - 0.9) < 0.01)
        #expect(TextColor.presets.count >= 8 && Set(TextColor.presets.map(\.color)).count == TextColor.presets.count)
    }

    @Test func sizeIsContinuousClampedAndKnowsItsPreset() {
        var project = StudioProject(duration: 10)
        let id = project.addText(at: 1)
        #expect(project.text(id)?.sizePreset == .medium)
        project.updateText(id) { $0.heightFraction = 0.09 }
        #expect(project.text(id)?.sizePreset == nil && project.text(id)?.heightFraction == 0.09)
        project.updateText(id) { $0.heightFraction = 5 }
        #expect(project.text(id)?.heightFraction == TextOverlay.sizeRange.upperBound)
        project.updateText(id) { $0.heightFraction = 0 }
        #expect(project.text(id)?.heightFraction == TextOverlay.sizeRange.lowerBound)
        project.updateText(id) { $0.heightFraction = TextOverlay.Size.huge.heightFraction }
        #expect(project.text(id)?.sizePreset == .huge)
    }
}
