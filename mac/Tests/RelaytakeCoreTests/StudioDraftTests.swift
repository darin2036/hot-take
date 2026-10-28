import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct StudioDraftTests {
    private func editedProject() throws -> StudioProject {
        var project = StudioProject(duration: 20)
        project.splice(at: 8)
        try project.remove(TimeSpan(start: 2, end: 4))
        project.texts = [TextOverlay(text: "Hello", start: 1, end: 3)]
        project.zooms = [ZoomSegment(start: 5, end: 7, x: 0.3, y: 0.6, scale: 2)]
        project.background = .standard
        project.captions = StudioCaptions(style: .bold, position: .top, cues: [CaptionSegment(start: 0, end: 2, text: "Hi")])
        project.originalVolume = 0
        return project
    }

    private func tempFiles() -> TakeFiles {
        TakeFiles(directory: FileManager.default.temporaryDirectory.appendingPathComponent("draft-\(UUID().uuidString)"), baseName: "Take")
    }

    @Test func aDraftRoundTripsThroughDiskAndRestoresTheSameProject() throws {
        let project = try editedProject()
        let store = StudioDraftStore(files: tempFiles())
        defer { store.discard() }
        #expect(store.write(try #require(store.encode(StudioDraft(project: project, playhead: 6.5)))))
        let draft = try #require(store.load())
        #expect(draft.playhead == 6.5)
        let restored = try #require(draft.project(duration: 20, cameraSource: nil))
        #expect(restored == project)
        #expect(restored.isEdited)
    }

    @Test func aDraftForADifferentRecordingIsIgnored() throws {
        let draft = StudioDraft(project: try editedProject(), playhead: 0)
        #expect(draft.project(duration: 35, cameraSource: nil) == nil)
    }

    @Test func missingAudioFilesAreDroppedButTheRestIsKept() throws {
        var project = try editedProject()
        let gone = URL(fileURLWithPath: "/nonexistent/music.m4a")
        project.clips = [AudioClip(kind: .music, url: gone, name: "Music", sourceDuration: 30, length: 10)]
        let restored = try #require(StudioDraft(project: project, playhead: 0).project(duration: 20, cameraSource: nil))
        #expect(restored.clips.isEmpty)
        #expect(restored.texts.count == 1)
    }

    @Test func damagedCutsFallBackToTheWholeRecording() {
        let cuts = EditModel(duration: 10, segments: [TimeSpan(start: 4, end: 4.01), TimeSpan(start: .nan, end: 3)])
        #expect(cuts.segments == [TimeSpan(start: 0, end: 10)])
        let clamped = EditModel(duration: 10, segments: [TimeSpan(start: -2, end: 5), TimeSpan(start: 6, end: 99)])
        #expect(clamped.segments == [TimeSpan(start: 0, end: 5), TimeSpan(start: 6, end: 10)])
    }

    @Test func unreadableOrNewerDraftsAreIgnoredAndDiscardRemovesTheFolder() throws {
        let files = tempFiles()
        let store = StudioDraftStore(files: files)
        #expect(store.load() == nil)
        #expect(store.write(Data("not json".utf8)))
        #expect(store.load() == nil)
        var draft = StudioDraft(project: try editedProject(), playhead: 0)
        draft.version = StudioDraft.currentVersion + 1
        #expect(draft.project(duration: 20, cameraSource: nil) == nil)
        store.discard()
        #expect(!FileManager.default.fileExists(atPath: files.draftsDirectory.path))
    }
}
