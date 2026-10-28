import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct HotTakeFileTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hottake-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sample(_ directory: URL) throws -> (URL, [PackageSource]) {
        let big = directory.appendingPathComponent("big.bin")
        try Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: big)
        let sources = [
            PackageSource(id: "a", role: .video, name: "take.mp4", content: .file(big)),
            PackageSource(id: "b", role: .draft, name: "edit.json", content: .data(Data("{\"x\":1}".utf8))),
            PackageSource(id: "c", role: .audio, name: "empty.m4a", content: .data(Data())),
        ]
        return (directory.appendingPathComponent("out.hottake"), sources)
    }

    @Test func aFileRoundTripsItsBlobsExactly() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (destination, sources) = try sample(dir)
        try HotTakeFile.write(title: "Demo", revision: 3, sources: sources, to: destination)
        let reader = try HotTakeFile.open(destination)
        #expect(reader.manifest.title == "Demo" && reader.manifest.revision == 3 && reader.manifest.entries.count == 3)
        let video = try #require(reader.entry(.video))
        let out = dir.appendingPathComponent("copy.mp4")
        try reader.extract(video, to: out)
        #expect(try Data(contentsOf: out) == Data(contentsOf: dir.appendingPathComponent("big.bin")))
        #expect(try reader.data(try #require(reader.entry(.draft))) == Data("{\"x\":1}".utf8))
        #expect(try reader.data(try #require(reader.entry(.audio))).isEmpty)
        #expect(video.fileExtension == "mp4")
    }

    @Test func aFileThatIsNotOursOrIsCutShortIsRefusedPolitely() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = dir.appendingPathComponent("note.hottake")
        try Data("hello there, this is plainly not a Hot Take file at all, just words".utf8).write(to: text)
        #expect(throws: PackageError.notAPackage) { try HotTakeFile.open(text) }

        let (destination, sources) = try sample(dir)
        try HotTakeFile.write(title: "Demo", revision: 1, sources: sources, to: destination)
        let whole = try Data(contentsOf: destination)
        let cut = dir.appendingPathComponent("cut.hottake")
        try whole.prefix(whole.count - 500).write(to: cut)
        #expect(throws: PackageError.self) { try HotTakeFile.open(cut) }
    }

    @Test func aFlippedByteInAnItemIsCaughtAndLeavesNothingBehind() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (destination, sources) = try sample(dir)
        try HotTakeFile.write(title: "Demo", revision: 1, sources: sources, to: destination)
        var bytes = try Data(contentsOf: destination)
        bytes[1_000_000] ^= 0xFF
        try bytes.write(to: destination)
        let reader = try HotTakeFile.open(destination)  // the table is intact; the damage is in the item
        let out = dir.appendingPathComponent("bad.mp4")
        #expect(throws: PackageError.self) { try reader.extract(try #require(reader.entry(.video)), to: out) }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func aDamagedTableOfContentsIsCaught() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (destination, sources) = try sample(dir)
        try HotTakeFile.write(title: "Demo", revision: 1, sources: sources, to: destination)
        var bytes = try Data(contentsOf: destination)
        bytes[bytes.count - 56 - 20] ^= 0x01  // inside the manifest
        try bytes.write(to: destination)
        #expect(throws: PackageError.self) { try HotTakeFile.open(destination) }
    }

    @Test func aNewerFormatIsRefusedWithAnUpdateMessage() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (destination, sources) = try sample(dir)
        try HotTakeFile.write(title: "Demo", revision: 1, sources: sources, to: destination)
        var bytes = try Data(contentsOf: destination)
        bytes[8] = 9
        try bytes.write(to: destination)
        #expect(throws: PackageError.newerFormat(9)) { try HotTakeFile.open(destination) }
    }

    @Test func savingOverAnExistingFileReplacesItWholeAndLeavesNoTemporaryFiles() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (destination, sources) = try sample(dir)
        try HotTakeFile.write(title: "One", revision: 1, sources: sources, to: destination)
        try HotTakeFile.write(title: "Two", revision: 2, sources: sources, to: destination)
        #expect(try HotTakeFile.open(destination).manifest.title == "Two")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("partial") }
        #expect(leftovers.isEmpty)
    }
}

@Suite struct TakePackageTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hottake-take-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aTakeWithAnEditTravelsAndComesBackAsANewTake() throws {
        let sender = try folder(), receiver = try folder()
        defer { try? FileManager.default.removeItem(at: sender); try? FileManager.default.removeItem(at: receiver) }
        let files = TakeFiles(directory: sender, baseName: "Hot Take 2026-10-27 at 09.00.00")
        try Data("video-bytes".utf8).write(to: files.video)
        let metadata = TakeMetadata(title: "Login bug", summary: "s", created: Date(timeIntervalSince1970: 0), derivedFrom: "Other take")
        try metadata.encoded().write(to: files.metadata)
        let song = sender.appendingPathComponent("song.m4a")
        try Data("song-bytes".utf8).write(to: song)

        var project = StudioProject(duration: 20)
        project.addMusic(url: song, name: "song", fileDuration: 30)
        project.addText(at: 2, text: "Look here")
        project.addZoom(at: 5)
        let draft = StudioDraft(project: project, playhead: 4)

        let file = sender.appendingPathComponent("share.hottake")
        try TakePackage.export(files: files, title: "Login bug", draft: draft, to: file)
        let raw = try String(decoding: Data(contentsOf: file), as: UTF8.self)
        #expect(!raw.contains(sender.path))  // nobody's folder names travel with the file

        let imported = try TakePackage.importPackage(from: file, into: receiver)
        #expect(imported.hasEdit && imported.revision == 1 && imported.files.baseName == "Login bug")
        #expect(try Data(contentsOf: imported.files.video) == Data("video-bytes".utf8))
        let restored = try TakeMetadata.decode(Data(contentsOf: imported.files.metadata))
        #expect(restored.title == "Login bug" && restored.derivedFrom == nil)
        let loaded = try #require(StudioDraftStore(files: imported.files).load())
        let back = try #require(loaded.project(duration: 20, cameraSource: nil))
        #expect(back.texts.map(\.text) == ["Look here"] && back.zooms.count == 1 && back.clips.count == 1)
        #expect(back.clips[0].url.path.hasPrefix(imported.files.audioDirectory.path))
        #expect(try Data(contentsOf: back.clips[0].url) == Data("song-bytes".utf8))
        #expect(loaded.playhead == 4 && loaded.sharedRevision == 1)

        // Importing the same file again never overwrites the first copy.
        let second = try TakePackage.importPackage(from: file, into: receiver)
        #expect(second.files.baseName == "Login bug 2")
    }

    @Test func aFileWithoutAnEditStillOpensAsAPlainTake() throws {
        let sender = try folder(), receiver = try folder()
        defer { try? FileManager.default.removeItem(at: sender); try? FileManager.default.removeItem(at: receiver) }
        let files = TakeFiles(directory: sender, baseName: "Plain")
        try Data("v".utf8).write(to: files.video)
        let file = sender.appendingPathComponent("p.hottake")
        try TakePackage.export(files: files, title: "Plain", draft: nil, to: file)
        let imported = try TakePackage.importPackage(from: file, into: receiver)
        #expect(!imported.hasEdit && FileManager.default.fileExists(atPath: imported.files.video.path))
    }

    @Test func aDamagedFileLeavesNothingInTheLibrary() throws {
        let sender = try folder(), receiver = try folder()
        defer { try? FileManager.default.removeItem(at: sender); try? FileManager.default.removeItem(at: receiver) }
        let files = TakeFiles(directory: sender, baseName: "Take")
        try Data(repeating: 7, count: 100_000).write(to: files.video)
        try Data("captions".utf8).write(to: files.captions)
        let file = sender.appendingPathComponent("t.hottake")
        try TakePackage.export(files: files, title: "Take", draft: nil, to: file)
        var bytes = try Data(contentsOf: file)
        // Damage the captions blob, which is extracted after the video.
        let reader = try HotTakeFile.open(file)
        let captions = try #require(reader.entry(.captions))
        bytes[Int(captions.offset)] ^= 0xFF
        try bytes.write(to: file)
        #expect(throws: PackageError.self) { try TakePackage.importPackage(from: file, into: receiver) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: receiver.path).isEmpty)
    }

    @Test func movingATakeCarriesItsSharedAudioAndRepointsTheDraft() throws {
        let sender = try folder(), library = try folder()
        defer { try? FileManager.default.removeItem(at: sender); try? FileManager.default.removeItem(at: library) }
        let files = TakeFiles(directory: sender, baseName: "Take")
        try Data("v".utf8).write(to: files.video)
        let song = sender.appendingPathComponent("s.m4a")
        try Data("song".utf8).write(to: song)
        var project = StudioProject(duration: 20)
        project.addMusic(url: song, name: "s", fileDuration: 30)
        let file = sender.appendingPathComponent("t.hottake")
        try TakePackage.export(files: files, title: "Take", draft: StudioDraft(project: project, playhead: 0), to: file)
        let imported = try TakePackage.importPackage(from: file, into: library)
        let folderName = try TakeLibrary.createFolder(named: "Sub", in: "", root: library)
        let entry = TakeEntry(files: imported.files, folder: "", created: Date(), title: "Take", summary: "", tags: [], hasCaptions: false)
        let moved = try TakeLibrary.move(entry, toFolder: folderName, root: library)
        let draft = try #require(StudioDraftStore(files: moved).load())
        #expect(draft.clips.count == 1 && FileManager.default.fileExists(atPath: draft.clips[0].url.path))
        #expect(draft.clips[0].url.path.hasPrefix(moved.audioDirectory.path))
    }
}
