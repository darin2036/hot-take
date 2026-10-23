import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct FolderIconTests {
    @Test func splitsAnEmojiFromTheTitle() {
        #expect(FolderName.split("🔥 Hot Takes") == ("🔥", "Hot Takes"))
        #expect(FolderName.split("⭐️Demos") == ("⭐️", "Demos"))
        #expect(FolderName.split("Demos").icon == nil)
        #expect(FolderName.split("2026 plans").icon == nil)  // digits are not icons
        #expect(FolderName.split("🔥").icon == nil)  // an emoji alone stays the name
        #expect(FolderName.compose(icon: "🎬", title: "Clips") == "🎬 Clips")
        #expect(FolderName.compose(icon: nil, title: "Clips") == "Clips")
        #expect(FolderName.compose(icon: "x", title: "Clips") == "Clips")  // not an emoji
    }

    @Test func renamingKeepsOrChangesTheIcon() {
        #expect(FolderName.renamed("🔥 Hot Takes", to: "Best Takes") == "🔥 Best Takes")
        #expect(FolderName.renamed("🔥 Hot Takes", to: "🎬 Clips") == "🎬 Clips")
        #expect(FolderName.renamed("🔥 Hot Takes", to: "🎬") == "🎬 Hot Takes")
        #expect(FolderName.renamed("Demos", to: "Demos 2") == "Demos 2")
    }

    @Test func folderNodesExposeIconAndTitle() {
        let node = FolderNode(name: "💡 Ideas", path: "💡 Ideas", children: [])
        #expect(node.icon == "💡" && node.title == "Ideas")
    }

    @Test func settingAndRemovingAnIconRenamesTheRealFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("icons-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Demos"), withIntermediateDirectories: true)
        var path = try TakeLibrary.setFolderIcon("Demos", to: "🎬", root: root)
        #expect(path == "🎬 Demos" && FileManager.default.fileExists(atPath: root.appendingPathComponent("🎬 Demos").path))
        path = try TakeLibrary.setFolderIcon(path, to: "🚀", root: root)
        #expect(path == "🚀 Demos")
        path = try TakeLibrary.setFolderIcon(path, to: nil, root: root)
        #expect(path == "Demos")
    }

    @Test func theDefaultFolderIsCreatedOnceAndNeverDuplicated() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("default-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try TakeLibrary.ensureDefaultFolder(root: root))  // makes the library itself too
        #expect(TakeLibrary.folders(in: root).map(\.name) == ["🔥 Hot Takes"])
        #expect(try !TakeLibrary.ensureDefaultFolder(root: root))
        // The same folder under another icon, or none, counts.
        try TakeLibrary.setFolderIcon("🔥 Hot Takes", to: nil, root: root)
        #expect(try !TakeLibrary.ensureDefaultFolder(root: root))
        #expect(TakeLibrary.folders(in: root).count == 1)
    }
}
