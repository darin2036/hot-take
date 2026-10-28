import AVFoundation
import AppKit
import Foundation
import RelaytakeCore

enum LibraryScope: Hashable {
    case all
    case folder(String)
}

@MainActor
final class LibraryModel: ObservableObject {
    static let shared = LibraryModel()

    @Published private(set) var takes: [TakeEntry] = []
    @Published private(set) var folders: [FolderNode] = []
    /// The take open in the detail view; nil while browsing.
    @Published var selection: String?
    /// What the sidebar is showing: everything, or one folder's recordings.
    @Published var scope: LibraryScope = .all
    @Published var query = ""
    @Published private(set) var durations: [String: Double] = [:]
    @Published var error: String?

    /// Name dialogs (new folder, rename folder, rename take) are shared so any menu can open them.
    enum Prompt: Equatable {
        case newFolder(parent: String)
        case renameFolder(path: String)
        case renameTake(id: String)
    }
    @Published var prompt: Prompt?
    @Published var promptText = ""
    /// Asks before moving the checked recordings to the Trash.
    @Published var confirmBulkTrash = false
    /// Asks before moving the open recording to the Trash.
    @Published var confirmDetailTrash = false
    /// The Studio that is open, so the toolbar's Share sends its edited version rather than the original file.
    @Published var openStudio: StudioModel?
    /// While set, the video fills the whole window ("theater mode").
    @Published var theater: TheaterRequest?

    /// file-manager-style selection of recordings in the browser (distinct from `selection`, the open take).
    @Published private(set) var selectionState = SelectionState()
    var checked: Set<String> { selectionState.selected }

    let directory = TakeFiles.defaultDirectory()

    var selected: TakeEntry? { takes.first { $0.id == selection } }

    /// Originals whose saved versions are showing under them.
    @Published private(set) var expandedFamilies: Set<String> = []

    /// Every take for the current sidebar choice and search text, versions included.
    private var matchingTakes: [TakeEntry] {
        takes.filter { take in
            switch scope {
            case .all: true
            case .folder(let path): take.folder == path
            }
        }.filter { $0.matches(query) }
    }

    /// How many recordings match, counting versions that are folded away under their original.
    var matchingCount: Int { matchingTakes.count }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// What the browser lists: each original followed by its versions when opened. While searching, every
    /// match shows, so nothing is hidden inside a folded family.
    var visibleTakes: [TakeEntry] {
        TakeFamilies.arrange(matchingTakes, expanded: expandedFamilies, showAll: isSearching)
    }

    func versionCount(of take: TakeEntry) -> Int { TakeFamilies.versionCount(of: take.id, in: takes) }
    func isVersion(_ take: TakeEntry) -> Bool { TakeFamilies.isVersion(take, in: takes) }
    func isExpanded(_ take: TakeEntry) -> Bool { isSearching || expandedFamilies.contains(take.id) }

    /// Opens an original's versions (after a new one is saved, so it is easy to find).
    func expandVersions(of take: TakeEntry) { expandedFamilies.insert(take.id) }

    func toggleVersions(of take: TakeEntry) {
        if expandedFamilies.contains(take.id) { expandedFamilies.remove(take.id) } else { expandedFamilies.insert(take.id) }
    }

    /// The title of the recording a version was made from.
    func originalTitle(of take: TakeEntry) -> String? {
        let root = TakeFamilies.rootID(of: take, in: takes)
        return root == take.id ? nil : takes.first { $0.id == root }?.title
    }

    func count(in scope: LibraryScope) -> Int {
        switch scope {
        case .all: takes.count
        case .folder(let path): takes.filter { $0.folder == path }.count
        }
    }

    var scopeTitle: String {
        switch scope {
        case .all: "All Recordings"
        case .folder(let path): FolderName.split((path as NSString).lastPathComponent).title
        }
    }

    /// Where a new recording goes: the folder being viewed, else the top level.
    var recordingDirectory: URL {
        if case .folder(let path) = scope,
           let url = try? TakeLibrary.resolve(path, in: directory) { return url }
        return directory
    }

    /// Every folder in tree order with its depth, for "Move to" menus.
    var flatFolders: [(path: String, name: String, depth: Int)] {
        func walk(_ nodes: [FolderNode], _ depth: Int) -> [(String, String, Int)] {
            nodes.flatMap { [($0.path, $0.name, depth)] + walk($0.children, depth + 1) }
        }
        return walk(folders, 0).map { (path: $0.0, name: $0.1, depth: $0.2) }
    }

    /// The Hot Takes folder is created once per Mac, so a user who trashes it does not get it back.
    private func ensureDefaultFolderOnce() {
        let key = "createdDefaultFolder"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        if (try? TakeLibrary.ensureDefaultFolder(root: directory)) != nil { UserDefaults.standard.set(true, forKey: key) }
    }

    func refresh() {
        ensureDefaultFolderOnce()
        takes = TakeLibrary.load(directory: directory)
        folders = TakeLibrary.folders(in: directory)
        selectionState.prune(keeping: Set(takes.map(\.id)))
        if let selection, !takes.contains(where: { $0.id == selection }) { self.selection = nil }
        if case .folder(let path) = scope, !flatFolders.contains(where: { $0.path == path }) { scope = .all }
    }

    func select(files: TakeFiles) {
        refresh()
        let folder = TakeLibrary.relativePath(of: files.directory, in: directory)
        let id = folder.isEmpty ? files.baseName : folder + "/" + files.baseName
        if takes.contains(where: { $0.id == id }) { selection = id }
    }

    /// Switch the sidebar choice and go back to browsing.
    func show(_ newScope: LibraryScope) {
        scope = newScope
        selection = nil
        clearSelection()
    }

    // MARK: Name prompts

    func ask(_ newPrompt: Prompt) {
        switch newPrompt {
        case .newFolder: promptText = ""
        case .renameFolder(let path): promptText = FolderName.split((path as NSString).lastPathComponent).title
        case .renameTake(let id): promptText = takes.first { $0.id == id }?.title ?? ""
        }
        prompt = newPrompt
    }

    var promptTitle: String {
        switch prompt {
        case .newFolder(let parent):
            parent.isEmpty ? "New Folder" : "New Folder in “\((parent as NSString).lastPathComponent)”"
        case .renameFolder: "Rename Folder"
        case .renameTake: "Rename Recording"
        case nil: ""
        }
    }

    var promptConfirm: String {
        switch prompt {
        case .newFolder: "Create"
        default: "Rename"
        }
    }

    func commitPrompt() {
        let text = promptText
        switch prompt {
        case .newFolder(let parent): createFolder(named: text, in: parent)
        case .renameFolder(let path): renameFolder(path, to: FolderName.renamed((path as NSString).lastPathComponent, to: text))
        case .renameTake(let id):
            if let entry = takes.first(where: { $0.id == id }) {
                perform { try TakeLibrary.rename(entry, to: text); refresh() }
            }
        case nil: break
        }
        prompt = nil
    }

    /// Path of the folder being viewed, "" for All Recordings.
    var currentFolderPath: String {
        if case .folder(let path) = scope { path } else { "" }
    }

    func showInFinder() {
        let url = (try? TakeLibrary.resolve(currentFolderPath, in: directory)) ?? directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    func trashTake(_ entry: TakeEntry) {
        perform {
            try TakeLibrary.trash(entry)
            if selection == entry.id { selection = nil }
            refresh()
        }
    }

    // MARK: Selection (click, ⌘-click, ⇧-click, box, keyboard)

    private var visibleIDs: [String] { visibleTakes.map(\.id) }

    func click(_ id: String, command: Bool, shift: Bool) {
        selectionState.click(id, order: visibleIDs, command: command, shift: shift)
    }

    func checkAllVisible() { selectionState.selectAll(visibleIDs) }
    func clearSelection() { selectionState.clear() }
    func setSelection(_ ids: Set<String>) { selectionState.set(ids) }

    func boxSelect(hits: Set<String>, base: Set<String>, additive: Bool) {
        selectionState.box(hits: hits, base: base, additive: additive, order: visibleIDs)
    }

    func moveSelection(by offset: Int, extend: Bool) {
        selectionState.move(by: offset, order: visibleIDs, extend: extend)
    }

    /// What a drag of `id` carries: every selected recording if it is one of them, else just it.
    /// Ids are newline-joined so the payload stays a plain string.
    func dragPayload(for id: String) -> String {
        selectionState.contains(id) ? selectionState.ordered(by: visibleIDs).joined(separator: "\n") : id
    }

    /// Moves what a drag carried into `folder` ("" is the top level).
    func drop(_ payloads: [String], into folder: String) {
        let ids = payloads.flatMap { $0.split(separator: "\n").map(String.init) }
        move(ids: ids, to: folder)
        clearSelection()
    }

    /// Open the single selected recording (Return key or double-click).
    func openSelected() {
        if selectionState.count == 1, let id = selectionState.selected.first { selection = id }
    }

    /// Moves every checked recording to the Trash (never deletes permanently). Reports how many failed.
    func trashChecked() {
        let entries = takes.filter { checked.contains($0.id) }
        var failed = 0
        for entry in entries {
            do { try TakeLibrary.trash(entry) } catch { failed += 1 }
        }
        if failed > 0 { self.error = "\(failed) of \(entries.count) recordings could not be moved to the Trash." }
        clearSelection()
        refresh()
    }

    func moveChecked(to folder: String) {
        move(ids: selectionState.ordered(by: visibleIDs), to: folder)
        clearSelection()
    }

    // MARK: Folders and moving

    func createFolder(named name: String, in parent: String) {
        perform {
            let path = try TakeLibrary.createFolder(named: name, in: parent, root: directory)
            refresh()
            show(.folder(path))
        }
    }

    func renameFolder(_ path: String, to name: String) {
        perform {
            let newPath = try TakeLibrary.renameFolder(path, to: name, root: directory)
            if case .folder(let current) = scope, current == path || current.hasPrefix(path + "/") {
                scope = .folder(newPath + current.dropFirst(path.count))
            }
            refresh()
        }
    }

    /// Sets (or with nil removes) a folder's emoji icon.
    func setFolderIcon(_ path: String, to icon: String?) {
        perform {
            let newPath = try TakeLibrary.setFolderIcon(path, to: icon, root: directory)
            if case .folder(let current) = scope, current == path || current.hasPrefix(path + "/") {
                scope = .folder(newPath + current.dropFirst(path.count))
            }
            refresh()
        }
    }

    func trashFolder(_ path: String) {
        perform {
            try TakeLibrary.trashFolder(path, root: directory)
            if case .folder(let current) = scope, current == path || current.hasPrefix(path + "/") { scope = .all }
            selection = nil
            refresh()
        }
    }

    /// Moves takes (by id) into `folder`; "" is the top level.
    func move(ids: [String], to folder: String) {
        perform {
            var openedTakeMovedTo: TakeFiles?
            // An original takes its versions along, so a family is never split between folders.
            var family: [String] = []
            for id in ids {
                family.append(id)
                for take in takes where take.id != id && TakeFamilies.rootID(of: take, in: takes) == id && !ids.contains(take.id) {
                    family.append(take.id)
                }
            }
            for id in family {
                guard let entry = takes.first(where: { $0.id == id }) else { continue }
                let moved = try TakeLibrary.move(entry, toFolder: folder, root: directory)
                if id == selection { openedTakeMovedTo = moved }
            }
            refresh()
            if let openedTakeMovedTo { select(files: openedTakeMovedTo) }
        }
    }

    private func perform(_ work: () throws -> Void) {
        do { try work() } catch { self.error = error.localizedDescription }
    }

    func duration(of entry: TakeEntry) async -> Double? {
        if let known = durations[entry.id] { return known }
        guard let seconds = try? await AVURLAsset(url: entry.files.video).load(.duration).seconds,
              seconds.isFinite else { return nil }
        durations[entry.id] = seconds
        return seconds
    }

    func thumbnail(for entry: TakeEntry) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: entry.files.video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)
        guard let result = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)) else { return nil }
        return NSImage(cgImage: result.image, size: .zero)
    }

    func trash(_ entry: TakeEntry) throws {
        try TakeLibrary.trash(entry)
        refresh()
    }
}
