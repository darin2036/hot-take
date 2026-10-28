import Foundation

/// One recording on disk with whatever sidecar data exists beside it.
public struct TakeEntry: Identifiable, Equatable, Sendable {
    /// What a recording without a title of its own is called in the library.
    public static let untitled = "Hot Takes"

    /// Unique across folders: "Folder/Sub/Name" (or just "Name" at the top level).
    public var id: String { folder.isEmpty ? files.baseName : folder + "/" + files.baseName }
    public let files: TakeFiles
    /// Path of the containing folder relative to the library root; "" at the top level.
    public let folder: String
    public let created: Date
    public let title: String
    public let summary: String
    public let tags: [String]
    public let hasCaptions: Bool
    /// The file name of the recording this one is a copy of, if it is: recorded when the copy was saved, or
    /// worked out from "(edited)" in the name for older copies. It may not exist any more.
    public var originalName: String? = nil
    /// The moment chosen as this take's picture in the library, if any.
    public var thumbnailTime: Double? = nil

    /// Whether `text` matches the title, summary, tags or folder name (case-insensitive).
    public func matches(_ text: String) -> Bool {
        let needle = text.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return ([title, summary, folder] + tags).contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

public struct FolderNode: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let name: String
    /// Relative to the library root, e.g. "Demos/Q4".
    public let path: String
    public let children: [FolderNode]
    /// SwiftUI's hierarchical lists want nil for leaves.
    public var childrenOrNil: [FolderNode]? { children.isEmpty ? nil : children }
}

public enum LibraryError: LocalizedError, Equatable {
    case invalidName
    case outsideLibrary
    case missing(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a name for the folder."
        case .outsideLibrary: "That location is outside the Hot Take folder."
        case .missing(let name): "\(name) could not be found."
        }
    }
}

/// Reads and edits the library folder. Titles, summaries, tags and notes live in the `.json`
/// sidecar; the video file name never changes unless a take is moved to avoid a name clash.
public enum TakeLibrary {
    // MARK: Reading

    /// Every take under `directory`, including subfolders, newest first. Hidden files and folders
    /// (such as in-progress work) are skipped.
    public static func load(directory: URL, fileManager: FileManager = .default) -> [TakeEntry] {
        let root = directory.standardizedFileURL
        guard let walker = fileManager.enumerator(
            at: root, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }

        var entries: [TakeEntry] = []
        for case let url as URL in walker where url.pathExtension.lowercased() == "mp4" {
            let parent = url.deletingLastPathComponent().standardizedFileURL
            let files = TakeFiles(directory: parent, baseName: url.deletingPathExtension().lastPathComponent)
            let metadata = metadata(for: files)
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            entries.append(
                TakeEntry(
                    files: files,
                    folder: relativePath(of: parent, in: root),
                    created: metadata?.created ?? values?.creationDate ?? values?.contentModificationDate ?? .distantPast,
                    title: metadata.flatMap { $0.title.isEmpty ? nil : $0.title } ?? TakeEntry.untitled,
                    summary: metadata?.summary ?? "",
                    tags: metadata?.tags ?? [],
                    hasCaptions: fileManager.fileExists(atPath: files.captions.path),
                    originalName: metadata?.derivedFrom ?? TakeFamilies.inferredOriginalName(of: files.baseName),
                    thumbnailTime: metadata?.thumbnailTime))
        }
        return entries.sorted { $0.created > $1.created }
    }

    /// The folder tree under `directory`, sorted by name. Hidden folders are skipped.
    public static func folders(in directory: URL, fileManager: FileManager = .default) -> [FolderNode] {
        func children(of url: URL, prefix: String) -> [FolderNode] {
            let items = (try? fileManager.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .map { item in
                    let path = prefix.isEmpty ? item.lastPathComponent : prefix + "/" + item.lastPathComponent
                    return FolderNode(name: item.lastPathComponent, path: path, children: children(of: item, prefix: path))
                }
        }
        return children(of: directory, prefix: "")
    }

    public static func metadata(for files: TakeFiles) -> TakeMetadata? {
        (try? Data(contentsOf: files.metadata)).flatMap { try? TakeMetadata.decode($0) }
    }

    // MARK: Editing metadata

    public static func rename(_ entry: TakeEntry, to title: String) throws {
        try update(entry) { $0.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Saves any combination of the editable fields; the rest are kept.
    public static func update(_ entry: TakeEntry, _ change: (inout TakeMetadata) -> Void) throws {
        var metadata = Self.metadata(for: entry.files)
            ?? TakeMetadata(title: "", summary: "", created: entry.created)
        change(&metadata)
        try metadata.encoded().write(to: entry.files.metadata, options: .atomic)
    }

    /// Saves a corrected transcript, and rewrites the captions file if the take has one so the two agree.
    /// Translations were made from the old words, so they are dropped.
    public static func saveTranscript(_ segments: [CaptionSegment], for entry: TakeEntry) throws {
        try update(entry) {
            $0.transcript = segments
            $0.translations = [:]
        }
        if FileManager.default.fileExists(atPath: entry.files.captions.path) {
            try Captions.webVTT(segments).write(to: entry.files.captions, atomically: true, encoding: .utf8)
        }
    }

    /// Saves what was seen while recording (clicks, and whether a screen, window or area was captured)
    /// beside the video, keeping anything already written there.
    public static func saveCapture(
        for files: TakeFiles, created: Date, clicks: [ClickEvent], kind: String, cameraOffset: Double? = nil,
        cameraPlacement: CameraPlacement? = nil
    ) throws {
        var metadata = Self.metadata(for: files) ?? TakeMetadata(title: "", summary: "", created: created)
        metadata.clicks = clicks
        metadata.captureKind = kind
        metadata.cameraOffset = cameraOffset
        metadata.cameraPlacement = cameraPlacement
        try metadata.encoded().write(to: files.metadata, options: .atomic)
    }

    /// Records that `copy` was made from `original` (both in the same folder), keeping anything already in
    /// the copy's notes file.
    public static func link(copy: TakeFiles, to original: TakeFiles, created: Date) throws {
        var metadata = Self.metadata(for: copy) ?? TakeMetadata(title: "", summary: "", created: created)
        metadata.derivedFrom = original.baseName
        try metadata.encoded().write(to: copy.metadata, options: .atomic)
    }

    // MARK: Copies and trash

    /// "Name (edited)", then "Name (edited 2)" … so a saved copy never overwrites anything.
    public static func uniqueCopyName(basedOn name: String, in directory: URL, fileManager: FileManager = .default) -> String {
        var candidate = "\(name) (edited)"
        var number = 2
        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).appendingPathExtension("mp4").path) {
            candidate = "\(name) (edited \(number))"
            number += 1
        }
        return candidate
    }

    /// Moves the take's files to the Trash. Never deletes permanently.
    public static func trash(_ entry: TakeEntry, fileManager: FileManager = .default) throws {
        for url in [entry.files.video, entry.files.captions, entry.files.metadata, entry.files.screenOriginal, entry.files.cameraOriginal, entry.files.draft, entry.files.agentDirectory]
            + entry.files.audioFiles()
        where fileManager.fileExists(atPath: url.path) {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
        }
    }

    // MARK: Folders

    /// Creates a folder named `name` inside `parent` (a relative path, "" for the top level).
    /// A clashing name gets " 2", " 3"… Returns the new folder's relative path.
    @discardableResult
    public static func createFolder(named name: String, in parent: String, root: URL, fileManager: FileManager = .default) throws -> String {
        let clean = sanitized(name)
        guard !clean.isEmpty else { throw LibraryError.invalidName }
        let parentURL = try resolve(parent, in: root)
        var candidate = clean
        var number = 2
        while fileManager.fileExists(atPath: parentURL.appendingPathComponent(candidate).path) {
            candidate = "\(clean) \(number)"
            number += 1
        }
        try fileManager.createDirectory(at: parentURL.appendingPathComponent(candidate), withIntermediateDirectories: false)
        return parent.isEmpty ? candidate : parent + "/" + candidate
    }

    /// Renames a folder in place. Returns its new relative path.
    @discardableResult
    public static func renameFolder(_ path: String, to name: String, root: URL, fileManager: FileManager = .default) throws -> String {
        let clean = sanitized(name)
        guard !clean.isEmpty, !path.isEmpty else { throw LibraryError.invalidName }
        let source = try resolve(path, in: root)
        let destination = source.deletingLastPathComponent().appendingPathComponent(clean)
        if destination.standardizedFileURL != source.standardizedFileURL {
            guard !fileManager.fileExists(atPath: destination.path) else { throw LibraryError.invalidName }
            try fileManager.moveItem(at: source, to: destination)
        }
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? clean : parent + "/" + clean
    }

    /// Moves a folder and everything in it to the Trash.
    public static func trashFolder(_ path: String, root: URL, fileManager: FileManager = .default) throws {
        guard !path.isEmpty else { throw LibraryError.invalidName }
        try fileManager.trashItem(at: try resolve(path, in: root), resultingItemURL: nil)
    }

    /// Moves a take (video, captions and notes together) into `folder`. A name clash gets a
    /// numeric suffix on all three files. Returns the take's new location.
    @discardableResult
    public static func move(_ entry: TakeEntry, toFolder folder: String, root: URL, fileManager: FileManager = .default) throws -> TakeFiles {
        let destination = try resolve(folder, in: root)
        if destination.standardizedFileURL == entry.files.directory.standardizedFileURL { return entry.files }

        var baseName = entry.files.baseName
        var number = 2
        func target(_ name: String) -> TakeFiles { TakeFiles(directory: destination, baseName: name) }
        while [target(baseName).video, target(baseName).captions, target(baseName).metadata]
            .contains(where: { fileManager.fileExists(atPath: $0.path) }) {
            baseName = "\(entry.files.baseName) \(number)"
            number += 1
        }
        let moved = target(baseName)
        let pairs = [
            (entry.files.video, moved.video), (entry.files.captions, moved.captions),
            (entry.files.metadata, moved.metadata),
            (entry.files.screenOriginal, moved.screenOriginal), (entry.files.cameraOriginal, moved.cameraOriginal),
            (entry.files.draft, moved.draft), (entry.files.agentDirectory, moved.agentDirectory),
        ]
        // Audio that came with a shared take moves with it.
        let audioPairs = entry.files.audioFiles().map { from -> (URL, URL) in
            let suffix = String(from.lastPathComponent.dropFirst(entry.files.baseName.count))
            return (from, moved.audioDirectory.appendingPathComponent(moved.baseName + suffix))
        }
        for (from, to) in pairs + audioPairs where fileManager.fileExists(atPath: from.path) {
            if from.deletingLastPathComponent() != to.deletingLastPathComponent() {
                try fileManager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            try fileManager.moveItem(at: from, to: to)
        }
        // The draft names its audio files by path, so follow them to the new place.
        let store = StudioDraftStore(files: moved)
        if var draft = store.load() {
            let oldPrefix = entry.files.audioDirectory.path + "/" + entry.files.baseName
            for index in draft.clips.indices where draft.clips[index].url.path.hasPrefix(oldPrefix) {
                let suffix = String(draft.clips[index].url.lastPathComponent.dropFirst(entry.files.baseName.count))
                draft.clips[index].url = moved.audioDirectory.appendingPathComponent(moved.baseName + suffix)
            }
            if let data = store.encode(draft) { store.write(data) }
        }
        return moved
    }

    // MARK: Helpers

    /// Folder names can't contain path separators or colons, or start with a dot.
    static func sanitized(_ name: String) -> String {
        var clean = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.hasPrefix(".") { clean.removeFirst() }
        return clean
    }

    /// Resolves a relative folder path under `root`, refusing anything that escapes it.
    public static func resolve(_ path: String, in root: URL) throws -> URL {
        let base = root.standardizedFileURL
        let url = (path.isEmpty ? base : base.appendingPathComponent(path)).standardizedFileURL
        guard url.path == base.path || url.path.hasPrefix(base.path + "/") else { throw LibraryError.outsideLibrary }
        guard FileManager.default.fileExists(atPath: url.path) else { throw LibraryError.missing(path.isEmpty ? "The library folder" : path) }
        return url
    }

    public static func relativePath(of directory: URL, in root: URL) -> String {
        let base = root.standardizedFileURL.path
        let path = directory.standardizedFileURL.path
        guard path.hasPrefix(base + "/") else { return "" }
        return String(path.dropFirst(base.count + 1))
    }
}


/// Copies saved from the Studio sit under the recording they came from: an original, then its versions
/// (and versions of versions) oldest to newest.
public enum TakeFamilies {
    /// "Demo (edited)" and "Demo (edited 2)" are copies of "Demo". Copies made before the link was recorded
    /// are recognized by this name.
    public static func inferredOriginalName(of baseName: String) -> String? {
        guard baseName.hasSuffix(")"), let open = baseName.range(of: " (edited", options: .backwards) else { return nil }
        let tail = baseName[open.upperBound...].dropLast()  // "" or " 2"
        guard tail.isEmpty || (tail.first == " " && tail.dropFirst().allSatisfy(\.isNumber) && tail.count > 1) else { return nil }
        let name = String(baseName[..<open.lowerBound])
        return name.isEmpty ? nil : name
    }

    private static func parentID(of take: TakeEntry, in byID: [String: TakeEntry]) -> String? {
        guard let name = take.originalName else { return nil }
        let id = take.folder.isEmpty ? name : take.folder + "/" + name
        return id != take.id && byID[id] != nil ? id : nil
    }

    /// The id of the original a take ultimately comes from (its own id if it is not a copy of anything here).
    public static func rootID(of take: TakeEntry, in takes: [TakeEntry]) -> String {
        let byID = Dictionary(takes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var current = take
        var steps = 0
        while let parent = parentID(of: current, in: byID), let next = byID[parent], steps < 32 {
            current = next
            steps += 1
        }
        return current.id
    }

    /// How many versions an original has (copies of it, and copies of those).
    public static func versionCount(of id: String, in takes: [TakeEntry]) -> Int {
        takes.filter { $0.id != id && rootID(of: $0, in: takes) == id }.count
    }

    /// Whether a take is a copy of another one in `takes`.
    public static func isVersion(_ take: TakeEntry, in takes: [TakeEntry]) -> Bool {
        rootID(of: take, in: takes) != take.id
    }

    /// Puts each family together, newest family first (by its newest member), the original first and its
    /// versions after it, oldest to newest. A family shows only its original unless it is in `expanded` or
    /// `showAll` is set (as when searching, so a match inside a family is never hidden).
    public static func arrange(_ takes: [TakeEntry], expanded: Set<String>, showAll: Bool = false) -> [TakeEntry] {
        var order: [String] = []
        var members: [String: [TakeEntry]] = [:]
        for take in takes {
            let root = rootID(of: take, in: takes)
            if members[root] == nil { order.append(root) }
            members[root, default: []].append(take)
        }
        func newest(_ id: String) -> Date { members[id]?.map(\.created).max() ?? .distantPast }
        let roots = order.enumerated().sorted { newest($0.element) != newest($1.element) ? newest($0.element) > newest($1.element) : $0.offset < $1.offset }
            .map(\.element)
        var result: [TakeEntry] = []
        for root in roots {
            let family = members[root] ?? []
            guard let original = family.first(where: { $0.id == root }) else {
                // The original is not in this list (filtered out, or gone): its versions stand on their own.
                result.append(contentsOf: family.sorted { $0.created > $1.created })
                continue
            }
            result.append(original)
            if showAll || expanded.contains(root) {
                result.append(contentsOf: family.filter { $0.id != root }.sorted { $0.created < $1.created })
            }
        }
        return result
    }
}
