import Foundation
import Testing

@testable import RelaytakeCore

private func entry(_ name: String, folder: String = "", at seconds: Double, originalName: String? = nil) -> TakeEntry {
    TakeEntry(
        files: TakeFiles(directory: URL(fileURLWithPath: "/tmp/lib/\(folder)"), baseName: name), folder: folder,
        created: Date(timeIntervalSince1970: seconds), title: name, summary: "", tags: [], hasCaptions: false,
        originalName: originalName ?? TakeFamilies.inferredOriginalName(of: name))
}

@Suite struct TakeFamilyTests {
    @Test func editedNamesPointBackAtTheirOriginal() {
        #expect(TakeFamilies.inferredOriginalName(of: "Demo (edited)") == "Demo")
        #expect(TakeFamilies.inferredOriginalName(of: "Demo (edited 3)") == "Demo")
        #expect(TakeFamilies.inferredOriginalName(of: "Demo (edited) (edited)") == "Demo (edited)")
        #expect(TakeFamilies.inferredOriginalName(of: "Demo") == nil)
        #expect(TakeFamilies.inferredOriginalName(of: "Demo (edited foo)") == nil)
        #expect(TakeFamilies.inferredOriginalName(of: " (edited)") == nil)
    }

    @Test func versionsSitUnderTheirOriginalOldestToNewest() {
        let takes = [
            entry("Other", at: 50),
            entry("Demo (edited 2)", at: 40),
            entry("Demo (edited)", at: 30),
            entry("Demo", at: 10),
        ]
        let shown = TakeFamilies.arrange(takes, expanded: ["Demo"]).map(\.files.baseName)
        #expect(shown == ["Other", "Demo", "Demo (edited)", "Demo (edited 2)"])
    }

    @Test func aCollapsedFamilyShowsOnlyItsOriginalAndFamiliesOrderByTheirNewestMember() {
        let takes = [
            entry("Newer", at: 20),
            entry("Demo (edited)", at: 30),  // an edit makes the Demo family the most recent
            entry("Demo", at: 10),
        ]
        #expect(TakeFamilies.arrange(takes, expanded: []).map(\.files.baseName) == ["Demo", "Newer"])
        #expect(TakeFamilies.arrange(takes, expanded: [], showAll: true).map(\.files.baseName) == ["Demo", "Demo (edited)", "Newer"])
        #expect(TakeFamilies.versionCount(of: "Demo", in: takes) == 1)
        #expect(TakeFamilies.versionCount(of: "Newer", in: takes) == 0)
    }

    @Test func aCopyOfACopyBelongsToTheSameFamily() {
        let takes = [entry("A", at: 1), entry("A (edited)", at: 2), entry("A (edited) (edited)", at: 3)]
        #expect(TakeFamilies.rootID(of: takes[2], in: takes) == "A")
        #expect(TakeFamilies.versionCount(of: "A", in: takes) == 2)
        #expect(TakeFamilies.arrange(takes, expanded: ["A"]).map(\.files.baseName) == ["A", "A (edited)", "A (edited) (edited)"])
    }

    @Test func aCopyWhoseOriginalIsGoneOrElsewhereStandsOnItsOwn() {
        let takes = [entry("Demo (edited)", at: 5), entry("Demo", folder: "Elsewhere", at: 1)]
        #expect(TakeFamilies.arrange(takes, expanded: []).map(\.files.baseName) == ["Demo (edited)", "Demo"])
        #expect(!TakeFamilies.isVersion(takes[0], in: takes))
    }

    @Test func theRecordedLinkWinsOverTheName() {
        let takes = [entry("Original", at: 1), entry("Something else", at: 2, originalName: "Original")]
        #expect(TakeFamilies.isVersion(takes[1], in: takes))
        #expect(TakeFamilies.arrange(takes, expanded: []).map(\.files.baseName) == ["Original"])
    }

    @Test func linkingACopyKeepsItsNotesAndSurvivesRewrites() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("family-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = TakeFiles(directory: folder, baseName: "Take")
        let copy = TakeFiles(directory: folder, baseName: "Renamed copy")
        try Data().write(to: original.video)
        try Data().write(to: copy.video)
        var notes = TakeMetadata(title: "Mine", summary: "S", created: Date(timeIntervalSince1970: 1_700_000_000))
        notes.notes = "keep me"
        try notes.encoded().write(to: copy.metadata)
        try TakeLibrary.link(copy: copy, to: original, created: Date())
        let linked = try #require(TakeLibrary.metadata(for: copy))
        #expect(linked.derivedFrom == "Take" && linked.notes == "keep me" && linked.title == "Mine")
        var rewritten = TakeMetadata(title: "New", summary: "", created: Date())
        rewritten.keepCapture(of: linked)
        #expect(rewritten.derivedFrom == "Take")
        // The library reads it back, even though the name says nothing.
        let takes = TakeLibrary.load(directory: folder)
        #expect(takes.first { $0.files.baseName == "Renamed copy" }?.originalName == "Take")
    }
}
