import CryptoKit
import Foundation

// The `.hottake` file: one self-contained file holding a recording, the edit made to it and everything the edit
// needs, so a take can be handed to someone else and opened exactly as it was left. It is Hot Take's own
// container (not a ZIP or a folder) and it is not encrypted.
//
//   "HOTTAKE1"  format version (UInt32, little endian)         header, 12 bytes
//   blob, blob, …                                              the media and data, back to back
//   manifest (JSON)                                            a table of the blobs: where, how long, SHA-256
//   manifest offset, manifest length (UInt64 × 2),
//   manifest SHA-256 (32 bytes), "HTKEND!!"                    footer, 56 bytes
//
// The manifest sits at the end so a file can be written in one pass, without knowing a blob's checksum before
// copying it. A reader starts from the footer. Nothing in the file is ever treated as a path: blobs are
// found by their offsets, and only the app decides where a blob is written.

/// What a blob is for. Unknown roles in a file are refused rather than guessed at.
public enum PackageRole: String, Codable, CaseIterable, Sendable {
    case video, screenOriginal, cameraOriginal, metadata, captions, draft, audio
}

public struct PackageEntry: Codable, Equatable, Sendable {
    public var id: String
    public var role: PackageRole
    /// A suggested file name, only used for its extension.
    public var name: String
    public var offset: UInt64
    public var length: UInt64
    public var sha256: String

    /// The extension to give the blob when it is written out: lowercase letters and digits only, at most 8.
    public var fileExtension: String {
        let ext = (name as NSString).pathExtension.lowercased()
        let safe = ext.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return safe.isEmpty || safe.count > 8 ? "bin" : safe
    }
}

public struct PackageManifest: Codable, Equatable, Sendable {
    public var format: Int
    /// The app that wrote the file, for support. Never used to decide how to read it.
    public var app: String
    public var title: String
    /// Counts up each time a file is saved from the same take, so people can see which copy is newer.
    public var revision: Int
    public var savedAt: Date
    public var entries: [PackageEntry]
}

public enum PackageError: LocalizedError, Equatable {
    case notAPackage
    case newerFormat(Int)
    case damaged(String)
    case missingPiece(String)

    public var errorDescription: String? {
        switch self {
        case .notAPackage: "This is not a Hot Take file."
        case .newerFormat: "This file was made by a newer version of Hot Take. Update the app to open it."
        case .damaged(let why): "This Hot Take file is damaged (\(why)). Ask for it to be sent again."
        case .missingPiece(let what): "This Hot Take file has no \(what)."
        }
    }
}

/// One thing to put in a file.
public struct PackageSource: Sendable {
    public enum Content: Sendable { case file(URL), data(Data) }
    public var id: String
    public var role: PackageRole
    public var name: String
    public var content: Content

    public init(id: String = UUID().uuidString, role: PackageRole, name: String, content: Content) {
        self.id = id
        self.role = role
        self.name = name
        self.content = content
    }
}

public enum HotTakeFile {
    public static let fileExtension = "hottake"
    public static let formatVersion = 1
    static let magic = Data("HOTTAKE1".utf8)
    static let footerMagic = Data("HTKEND!!".utf8)
    static let headerLength: UInt64 = 12
    static let footerLength: UInt64 = 56
    static let maxManifestLength: UInt64 = 4 << 20
    static let maxEntries = 2_000
    static let chunk = 1 << 20

    // MARK: Writing

    /// Writes a file in one pass: to a temporary file beside the destination, then moved into place, so a
    /// failure or a cancel never leaves a half-written file where a good one may have been.
    /// `progress` gets 0...1 as bytes are copied.
    public static func write(
        title: String, revision: Int, app: String = "Hot Take", savedAt: Date = Date(),
        sources: [PackageSource], to destination: URL,
        progress: (Double) -> Void = { _ in }, fileManager: FileManager = .default
    ) throws {
        guard sources.count <= maxEntries else { throw PackageError.damaged("too many items") }
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).partial-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: temporary.path, contents: nil) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        defer { try? fileManager.removeItem(at: temporary) }

        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }

        var header = magic
        header.append(littleEndian: UInt32(formatVersion))
        try output.write(contentsOf: header)

        let total = Double(max(1, sources.reduce(0) { $0 + size(of: $1, fileManager: fileManager) }))
        var done = 0.0
        var entries: [PackageEntry] = []
        var position = headerLength

        for source in sources {
            try Task.checkCancellation()
            var hash = SHA256()
            var length: UInt64 = 0
            switch source.content {
            case .data(let data):
                hash.update(data: data)
                try output.write(contentsOf: data)
                length = UInt64(data.count)
                done += Double(data.count)
                progress(done / total)
            case .file(let url):
                let input = try FileHandle(forReadingFrom: url)
                defer { try? input.close() }
                while true {
                    try Task.checkCancellation()
                    guard let piece = try input.read(upToCount: chunk), !piece.isEmpty else { break }
                    hash.update(data: piece)
                    try output.write(contentsOf: piece)
                    length += UInt64(piece.count)
                    done += Double(piece.count)
                    progress(done / total)
                }
            }
            entries.append(PackageEntry(
                id: source.id, role: source.role, name: source.name, offset: position, length: length,
                sha256: hex(hash.finalize())))
            position += length
        }

        let manifest = PackageManifest(
            format: formatVersion, app: app, title: title, revision: revision, savedAt: savedAt, entries: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        var footer = Data()
        footer.append(littleEndian: position)
        footer.append(littleEndian: UInt64(manifestData.count))
        footer.append(contentsOf: SHA256.hash(data: manifestData))
        footer.append(footerMagic)
        try output.write(contentsOf: manifestData)
        try output.write(contentsOf: footer)
        try output.synchronize()
        try output.close()

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
        progress(1)
    }

    private static func size(of source: PackageSource, fileManager: FileManager) -> Int {
        switch source.content {
        case .data(let data): return data.count
        case .file(let url):
            return ((try? fileManager.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
        }
    }

    // MARK: Reading

    /// Opens a file and checks its structure. Does not read the blobs: they are checked as they are used.
    public static func open(_ url: URL) throws -> Reader {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard fileSize >= headerLength + footerLength else { throw PackageError.notAPackage }

        try handle.seek(toOffset: 0)
        let header = try handle.read(upToCount: Int(headerLength)) ?? Data()
        guard header.count == Int(headerLength), header.prefix(magic.count) == magic else { throw PackageError.notAPackage }
        let version = Int(header.readLittleEndian(UInt32.self, at: magic.count))
        guard version <= formatVersion else { throw PackageError.newerFormat(version) }

        try handle.seek(toOffset: fileSize - footerLength)
        let footer = try handle.read(upToCount: Int(footerLength)) ?? Data()
        guard footer.count == Int(footerLength), footer.suffix(footerMagic.count) == footerMagic else {
            throw PackageError.damaged("the end of the file is missing; it may not have finished copying")
        }
        let manifestOffset = footer.readLittleEndian(UInt64.self, at: 0)
        let manifestLength = footer.readLittleEndian(UInt64.self, at: 8)
        let manifestHash = footer.subdata(in: 16..<48)
        let blobEnd = fileSize - footerLength
        guard manifestLength > 0, manifestLength <= maxManifestLength,
              manifestOffset >= headerLength, manifestOffset <= blobEnd,
              manifestLength <= blobEnd - manifestOffset, manifestOffset + manifestLength == blobEnd
        else { throw PackageError.damaged("the table of contents is out of place") }

        try handle.seek(toOffset: manifestOffset)
        let manifestData = try handle.read(upToCount: Int(manifestLength)) ?? Data()
        guard manifestData.count == Int(manifestLength), Data(SHA256.hash(data: manifestData)) == manifestHash else {
            throw PackageError.damaged("the table of contents does not match its checksum")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest: PackageManifest
        do { manifest = try decoder.decode(PackageManifest.self, from: manifestData) }
        catch { throw PackageError.damaged("the table of contents cannot be read") }
        guard manifest.format == version else { throw PackageError.damaged("the version numbers disagree") }
        try validate(manifest, blobEnd: manifestOffset)
        return Reader(url: url, manifest: manifest)
    }

    private static func validate(_ manifest: PackageManifest, blobEnd: UInt64) throws {
        guard manifest.entries.count <= maxEntries else { throw PackageError.damaged("too many items") }
        var ids = Set<String>()
        for entry in manifest.entries {
            guard ids.insert(entry.id).inserted else { throw PackageError.damaged("an item appears twice") }
            guard entry.offset >= headerLength, entry.offset <= blobEnd, entry.length <= blobEnd - entry.offset else {
                throw PackageError.damaged("an item lies outside the file")
            }
            guard entry.sha256.count == 64, entry.sha256.allSatisfy(\.isHexDigit) else {
                throw PackageError.damaged("an item has no checksum")
            }
        }
    }

    public struct Reader: Sendable {
        public let url: URL
        public let manifest: PackageManifest

        public func entries(_ role: PackageRole) -> [PackageEntry] { manifest.entries.filter { $0.role == role } }
        public func entry(_ role: PackageRole) -> PackageEntry? { entries(role).first }
        public func entry(id: String) -> PackageEntry? { manifest.entries.first { $0.id == id } }

        /// A small blob read into memory. Refuses anything over `limit`, so a bad file cannot ask for gigabytes.
        public func data(_ entry: PackageEntry, limit: Int = 64 << 20) throws -> Data {
            guard entry.length <= UInt64(limit) else { throw PackageError.damaged("an item is too large to be what it claims") }
            var data = Data()
            try copy(entry) { data.append($0) }
            return data
        }

        /// Writes a blob to `destination`, checking its checksum as it goes. A blob that fails the check leaves
        /// nothing behind.
        public func extract(_ entry: PackageEntry, to destination: URL, progress: (Double) -> Void = { _ in }) throws {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fileManager.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteNoPermission) }
            do {
                let output = try FileHandle(forWritingTo: destination)
                defer { try? output.close() }
                var written = 0.0
                try copy(entry) { piece in
                    try output.write(contentsOf: piece)
                    written += Double(piece.count)
                    progress(entry.length == 0 ? 1 : written / Double(entry.length))
                }
            } catch {
                try? fileManager.removeItem(at: destination)
                throw error
            }
        }

        private func copy(_ entry: PackageEntry, into sink: (Data) throws -> Void) throws {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: entry.offset)
            var hash = SHA256()
            var remaining = entry.length
            while remaining > 0 {
                try Task.checkCancellation()
                guard let piece = try handle.read(upToCount: Int(min(UInt64(HotTakeFile.chunk), remaining))), !piece.isEmpty else {
                    throw PackageError.damaged("an item is cut short")
                }
                hash.update(data: piece)
                try sink(piece)
                remaining -= UInt64(piece.count)
            }
            guard HotTakeFile.hex(hash.finalize()) == entry.sha256 else {
                throw PackageError.damaged("an item does not match its checksum")
            }
        }
    }

    fileprivate static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func readLittleEndian<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        var value: T = 0
        let size = MemoryLayout<T>.size
        for index in 0..<size { value |= T(truncatingIfNeeded: self[startIndex + offset + index]) << (8 * index) }
        return T(littleEndian: value)
    }
}
