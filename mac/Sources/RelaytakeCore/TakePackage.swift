import Foundation

/// Packs a take, and the edit made to it, into a `.hottake` file, and unpacks one into the library.
public enum TakePackage {
    /// Audio in a shared edit is named by this scheme and the blob's id, never by a path on the sender's Mac.
    static let mediaScheme = "hottake-media"

    public struct Imported: Equatable, Sendable {
        public var files: TakeFiles
        public var title: String
        public var revision: Int
        /// True when the file carried an unfinished edit, which the Studio picks up on opening.
        public var hasEdit: Bool
    }

    // MARK: Export

    /// Writes `files`' take, its metadata and captions, hidden originals, and the Studio edit in `draft` (if
    /// any) to `destination`. Audio the edit uses is copied in, so it plays on the other Mac.
    public static func export(
        files: TakeFiles, title: String, draft: StudioDraft?, to destination: URL,
        progress: (Double) -> Void = { _ in }, fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: files.video.path) else { throw PackageError.missingPiece("recording to share") }
        var sources: [PackageSource] = [PackageSource(role: .video, name: files.video.lastPathComponent, content: .file(files.video))]
        let optional: [(PackageRole, URL)] = [
            (.screenOriginal, files.screenOriginal), (.cameraOriginal, files.cameraOriginal),
            (.metadata, files.metadata), (.captions, files.captions),
        ]
        for (role, url) in optional where fileManager.fileExists(atPath: url.path) {
            sources.append(PackageSource(role: role, name: url.lastPathComponent, content: .file(url)))
        }

        var revision = 1
        if var shared = draft {
            var byPath: [String: String] = [:]
            var kept: [AudioClip] = []
            for var clip in shared.clips where fileManager.fileExists(atPath: clip.url.path) {
                let id = byPath[clip.url.path] ?? UUID().uuidString
                if byPath[clip.url.path] == nil {
                    byPath[clip.url.path] = id
                    sources.append(PackageSource(id: id, role: .audio, name: clip.url.lastPathComponent, content: .file(clip.url)))
                }
                clip.url = URL(string: "\(mediaScheme):\(id)")!
                kept.append(clip)
            }
            shared.clips = kept
            revision = (shared.sharedRevision ?? 0) + 1
            shared.sharedRevision = revision
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            sources.append(PackageSource(role: .draft, name: "edit.json", content: .data(try encoder.encode(shared))))
        }
        try HotTakeFile.write(title: title, revision: revision, sources: sources, to: destination, progress: progress, fileManager: fileManager)
    }

    // MARK: Import

    /// Unpacks a file into `directory` as a new take that never replaces an existing one. The edit, if there
    /// is one, becomes the take's Studio draft, so opening the take in the Studio continues the edit.
    /// Nothing is left behind if any part fails.
    public static func importPackage(
        from url: URL, into directory: URL, progress: @escaping (Double) -> Void = { _ in }, fileManager: FileManager = .default
    ) throws -> Imported {
        let reader = try HotTakeFile.open(url)
        guard reader.entry(.video) != nil else { throw PackageError.missingPiece("recording") }

        let title = reader.manifest.title
        let files = TakeFiles(directory: directory, baseName: uniqueBaseName(for: title, in: directory, fileManager: fileManager))
        var written: [URL] = []
        var failed = true
        defer { if failed { for url in written { try? fileManager.removeItem(at: url) } } }

        let singles: [(PackageRole, URL)] = [
            (.video, files.video), (.screenOriginal, files.screenOriginal), (.cameraOriginal, files.cameraOriginal),
            (.captions, files.captions),
        ]
        let weights = Double(max(1, reader.manifest.entries.reduce(0) { $0 + Int(clamping: $1.length) }))
        var done = 0.0
        func step(_ entry: PackageEntry) -> (Double) -> Void {
            let base = done
            return { fraction in progress((base + fraction * Double(entry.length)) / weights) }
        }
        for (role, destination) in singles {
            guard let entry = reader.entry(role) else { continue }
            try reader.extract(entry, to: destination, progress: step(entry))
            written.append(destination)
            done += Double(entry.length)
        }

        if let entry = reader.entry(.metadata) {
            // The copy it was made from belongs to someone else's library, so the link means nothing here.
            var metadata = try TakeMetadata.decode(try reader.data(entry))
            metadata.derivedFrom = nil
            try metadata.encoded().write(to: files.metadata, options: .atomic)
            written.append(files.metadata)
            done += Double(entry.length)
        }

        var hasEdit = false
        var revision = reader.manifest.revision
        if let entry = reader.entry(.draft) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var draft = try decoder.decode(StudioDraft.self, from: try reader.data(entry))
            var clips: [AudioClip] = []
            var number = 1
            var placed: [String: URL] = [:]
            for var clip in draft.clips {
                guard clip.url.scheme == mediaScheme, let blob = reader.entry(id: String(clip.url.absoluteString.dropFirst(mediaScheme.count + 1))),
                      blob.role == .audio else { continue }
                if placed[blob.id] == nil {
                    let destination = files.audioFile(number: number, extension: blob.fileExtension)
                    number += 1
                    try reader.extract(blob, to: destination, progress: step(blob))
                    written.append(destination)
                    done += Double(blob.length)
                    placed[blob.id] = destination
                }
                clip.url = placed[blob.id]!
                clips.append(clip)
            }
            draft.clips = clips
            revision = max(revision, draft.sharedRevision ?? 0)
            draft.sharedRevision = revision
            let store = StudioDraftStore(files: files)
            guard let data = store.encode(draft), store.write(data) else { throw CocoaError(.fileWriteUnknown) }
            written.append(files.draft)
            hasEdit = true
        }
        failed = false
        progress(1)
        return Imported(files: files, title: title, revision: revision, hasEdit: hasEdit)
    }

    /// A file name for the take that is free in `directory`: the title, then "title 2", "title 3"…
    static func uniqueBaseName(for title: String, in directory: URL, fileManager: FileManager) -> String {
        var base = TakeLibrary.sanitized(title)
        if base.isEmpty { base = "Shared Hot Take" }
        func free(_ name: String) -> Bool {
            let files = TakeFiles(directory: directory, baseName: name)
            return ![files.video, files.metadata, files.captions].contains { fileManager.fileExists(atPath: $0.path) }
        }
        var candidate = base
        var number = 2
        while !free(candidate) {
            candidate = "\(base) \(number)"
            number += 1
        }
        return candidate
    }
}
