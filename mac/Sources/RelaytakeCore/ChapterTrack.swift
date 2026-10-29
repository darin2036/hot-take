import Foundation

/// Adds chapters to an MP4 or MOV as a QuickTime chapter track. QuickTime Player, Apple's apps and most other players
/// (VLC, IINA, mpv) read that track as a chapter list: they show the names and jump to each one. The pictures and sound
/// are copied byte for byte. Only the movie header changes, and the offsets that point past it move by the same amount.
public enum ChapterTrack {
    public enum Failure: LocalizedError {
        case unsupportedFile

        public var errorDescription: String? {
            "Chapters cannot be added to this video's file layout."
        }
    }

    /// Writes a copy of `source` to `destination` (which must not exist) with `chapters` added. `duration` is the video's
    /// length in seconds. Chapters that start at or after the end are left out. With none left, the copy has no chapter
    /// track. A chapter track has no gaps, so a first chapter that starts after 0:00 is preceded by an untitled one.
    public static func add(_ chapters: [Chapter], duration: TimeInterval, from source: URL, to destination: URL) throws {
        let kept = ChapterList.normalized(chapters, duration: duration)
        guard !kept.isEmpty, duration > 0 else {
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }
        var marks = kept.map { (tick: ticks($0.start), title: $0.title) }
        if marks[0].tick > 0 { marks.insert((tick: 0, title: ""), at: 0) }
        let end = ticks(duration)
        let samples = marks.map { sampleData(title: $0.title) }
        let lengths = marks.indices.map { index in
            max(1, (index + 1 < marks.count ? marks[index + 1].tick : end) - marks[index].tick)
        }

        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let size = Int(try input.seekToEnd())
        let boxes = try topLevelBoxes(input, size: size)
        guard let moovEntry = boxes.first(where: { $0.name == "moov" }) else { throw Failure.unsupportedFile }
        let moovBytes = try read(input, from: moovEntry.start, count: moovEntry.size)
        guard var moov = try parse(moovBytes, from: 0, to: moovBytes.count).first, moov.name == "moov" else {
            throw Failure.unsupportedFile
        }

        let trackIndexes = moov.children.indices.filter { moov.children[$0].name == "trak" }
        guard let headerIndex = moov.children.firstIndex(where: { $0.name == "mvhd" }), !trackIndexes.isEmpty else {
            throw Failure.unsupportedFile
        }
        let header = moov.children[headerIndex].body
        let movieScale = try field(header, header.first == 1 ? 20 : 12, 4)
        // The header's last field is the next free track number; the chapter track takes it.
        let nextID = try field(header, header.count - 4, 4)
        let highestID = try trackIndexes.map { try trackID(moov.children[$0]) }.max() ?? 0
        let chapterID = max(nextID, highestID + 1)
        let lastField = header.count - 4
        moov.children[headerIndex].body.replaceSubrange(lastField..., with: bigEndian(chapterID + 1, bytes: 4))

        let video = trackIndexes.first { handler(of: moov.children[$0]) == "vide" } ?? trackIndexes[0]
        referenceChapters(chapterID, from: &moov.children[video])
        let movieDuration = Int((duration * Double(movieScale)).rounded())
        moov.children.append(chapterTrack(
            id: chapterID, movieDuration: movieDuration, total: end, samples: samples, lengths: lengths, dataOffset: 0))

        // Sizes do not depend on offset values, so the new size is known before the offsets are moved.
        let oldEnd = moovEntry.start + moovEntry.size
        let newSize = moov.serialized().count
        let delta = newSize - moovEntry.size
        for index in moov.children.indices {
            try shiftOffsets(&moov.children[index], past: oldEnd, by: delta)
        }
        let dataOffset = moovEntry.start + newSize + (size - oldEnd) + 8
        moov.children[moov.children.count - 1] = chapterTrack(
            id: chapterID, movieDuration: movieDuration, total: end, samples: samples, lengths: lengths, dataOffset: dataOffset)
        let newMoov = moov.serialized()
        guard newMoov.count == newSize else { throw Failure.unsupportedFile }

        // The chapter names go at the end, after everything that was already in the file.
        let chapterData = samples.flatMap { $0 }
        guard chapterData.count + 8 <= Int(UInt32.max) else { throw Failure.unsupportedFile }
        let mdat = bigEndian(chapterData.count + 8, bytes: 4) + Array("mdat".utf8) + chapterData
        do {
            try writeFile(destination) { output in
                try copy(input, from: 0, to: moovEntry.start, into: output)
                try output.write(contentsOf: Data(newMoov))
                try copy(input, from: oldEnd, to: size, into: output)
                try output.write(contentsOf: Data(mdat))
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    // MARK: Chapter track

    private static let language = 0x55C4  // "und"
    private static let identityMatrix = cat(
        bigEndian(0x0001_0000, bytes: 4), zeros(4), zeros(4), zeros(4),
        bigEndian(0x0001_0000, bytes: 4), zeros(4), zeros(4), zeros(4), bigEndian(0x4000_0000, bytes: 4))

    /// A text track of chapter names, one sample per chapter, each lasting until the next. It is not shown as video or
    /// sound (it is disabled in the movie), and the video track refers to it.
    private static func chapterTrack(
        id: Int, movieDuration: Int, total: Int, samples: [[UInt8]], lengths: [Int], dataOffset: Int
    ) -> Box {
        let sampleEntry = Box(name: "text", body: cat(zeros(6), bigEndian(1, bytes: 2), zeros(44)))
        let sampleDurations = lengths.map { cat(bigEndian(1, bytes: 4), bigEndian($0, bytes: 4)) }
        let sizes = samples.map { bigEndian($0.count, bytes: 4) }
        let stbl = Box(name: "stbl", children: [
            Box(name: "stsd", body: cat(zeros(4), bigEndian(1, bytes: 4), sampleEntry.serialized())),
            Box(name: "stts", body: cat(zeros(4), bigEndian(lengths.count, bytes: 4), cat(sampleDurations))),
            // Every sample sits in one chunk, which starts at the chapter data.
            Box(name: "stsc", body: cat(
                zeros(4), bigEndian(1, bytes: 4), bigEndian(1, bytes: 4), bigEndian(samples.count, bytes: 4), bigEndian(1, bytes: 4))),
            Box(name: "stsz", body: cat(zeros(4), bigEndian(0, bytes: 4), bigEndian(samples.count, bytes: 4), cat(sizes))),
            Box(name: "co64", body: cat(zeros(4), bigEndian(1, bytes: 4), bigEndian(dataOffset, bytes: 8))),
        ])
        let dataReference = Box(name: "url ", body: [0, 0, 0, 1])
        let minf = Box(name: "minf", children: [
            Box(name: "gmhd", children: [
                Box(name: "gmin", body: zeros(16)),
                Box(name: "text", body: identityMatrix),
            ]),
            Box(name: "dinf", children: [
                Box(name: "dref", body: cat(zeros(4), bigEndian(1, bytes: 4), dataReference.serialized())),
            ]),
            stbl,
        ])
        let mdia = Box(name: "mdia", children: [
            Box(name: "mdhd", body: cat(
                zeros(4), zeros(8), bigEndian(1000, bytes: 4), bigEndian(total, bytes: 4), bigEndian(language, bytes: 2), zeros(2))),
            Box(name: "hdlr", body: cat(zeros(8), Array("text".utf8), zeros(12), [0])),
            minf,
        ])
        let tkhd = Box(name: "tkhd", body: cat(
            zeros(4), zeros(8), bigEndian(id, bytes: 4), zeros(4), bigEndian(movieDuration, bytes: 4), zeros(16),
            identityMatrix, zeros(8)))
        return Box(name: "trak", children: [tkhd, mdia])
    }

    /// One chapter sample: its length and UTF-8 name, then an `encd` atom saying the name is UTF-8.
    private static func sampleData(title: String) -> [UInt8] {
        let text = Array(String(title.prefix(200)).utf8)
        return bigEndian(text.count, bytes: 2) + text + Box(name: "encd", body: bigEndian(0x100, bytes: 4)).serialized()
    }

    /// Points the video track at the chapter track, as players look for chapters through that reference.
    private static func referenceChapters(_ id: Int, from track: inout Box) {
        let reference = Box(name: "chap", body: bigEndian(id, bytes: 4))
        if let index = track.children.firstIndex(where: { $0.name == "tref" }) {
            track.children[index].children.append(reference)
        } else {
            let at = track.children.firstIndex(where: { $0.name == "mdia" }) ?? track.children.endIndex
            track.children.insert(Box(name: "tref", children: [reference]), at: at)
        }
    }

    private static func trackID(_ track: Box) throws -> Int {
        guard let header = track.children.first(where: { $0.name == "tkhd" }) else { throw Failure.unsupportedFile }
        return try field(header.body, header.body.first == 1 ? 20 : 12, 4)
    }

    private static func handler(of track: Box) -> String? {
        guard let media = track.children.first(where: { $0.name == "mdia" }),
              let header = media.children.first(where: { $0.name == "hdlr" }), header.body.count >= 12
        else { return nil }
        return String(decoding: header.body[8..<12], as: UTF8.self)
    }

    /// Moves every chunk offset at or past `threshold` by `delta`: the bytes after the old movie header moved by that much.
    private static func shiftOffsets(_ box: inout Box, past threshold: Int, by delta: Int) throws {
        if box.name == "stco" || box.name == "co64" {
            let width = box.name == "co64" ? 8 : 4
            let count = try field(box.body, 4, 4)
            for entry in 0..<count {
                let at = 8 + entry * width
                let value = try field(box.body, at, width)
                if value >= threshold {
                    box.body.replaceSubrange(at..<(at + width), with: bigEndian(value + delta, bytes: width))
                }
            }
        }
        for index in box.children.indices {
            try shiftOffsets(&box.children[index], past: threshold, by: delta)
        }
    }

    // MARK: Boxes

    /// A box in the file: a container holds children, any other box holds its bytes.
    private struct Box {
        var name: String
        var body: [UInt8] = []
        var children: [Box] = []

        static let containers: Set<String> = ["moov", "trak", "mdia", "minf", "stbl", "edts", "dinf", "udta", "tref"]

        func serialized() -> [UInt8] {
            var content = body
            for child in children { content += child.serialized() }
            let type = Array(name.utf8)
            if content.count + 8 <= Int(UInt32.max) {
                return bigEndian(content.count + 8, bytes: 4) + type + content
            }
            return bigEndian(1, bytes: 4) + type + bigEndian(content.count + 16, bytes: 8) + content
        }
    }

    private struct Entry {
        var name: String
        var start: Int
        var size: Int
    }

    private static func topLevelBoxes(_ handle: FileHandle, size: Int) throws -> [Entry] {
        var entries: [Entry] = []
        var position = 0
        while position < size {
            try handle.seek(toOffset: UInt64(position))
            let head = [UInt8](try handle.read(upToCount: 16) ?? Data())
            // Only the header is in hand here, so the box's size is checked against the file, not the buffer.
            let header = try readHeader(head, at: 0, end: Int.max)
            guard position + header.size <= size else { throw Failure.unsupportedFile }
            entries.append(Entry(name: header.name, start: position, size: header.size))
            position += header.size
        }
        return entries
    }

    private static func readHeader(_ bytes: [UInt8], at start: Int, end: Int) throws -> (name: String, size: Int, header: Int) {
        guard start + 8 <= end else { throw Failure.unsupportedFile }
        var size = try field(bytes, start, 4)
        var header = 8
        if size == 1 {
            guard start + 16 <= end else { throw Failure.unsupportedFile }
            size = try field(bytes, start + 8, 8)
            header = 16
        }
        // A size of 0 means "to the end of the file"; that layout cannot take more data after it.
        guard size >= header, start + size <= end else { throw Failure.unsupportedFile }
        return (String(decoding: bytes[(start + 4)..<(start + 8)], as: UTF8.self), size, header)
    }

    private static func parse(_ bytes: [UInt8], from start: Int, to end: Int) throws -> [Box] {
        var boxes: [Box] = []
        var at = start
        while at < end {
            let header = try readHeader(bytes, at: at, end: end)
            let contentStart = at + header.header, boxEnd = at + header.size
            if Box.containers.contains(header.name) {
                boxes.append(Box(name: header.name, children: try parse(bytes, from: contentStart, to: boxEnd)))
            } else {
                boxes.append(Box(name: header.name, body: Array(bytes[contentStart..<boxEnd])))
            }
            at = boxEnd
        }
        return boxes
    }

    // MARK: Bytes and files

    private static func ticks(_ seconds: TimeInterval) -> Int { Int((max(0, seconds) * 1000).rounded()) }

    private static func zeros(_ count: Int) -> [UInt8] { [UInt8](repeating: 0, count: count) }

    private static func cat(_ parts: [UInt8]...) -> [UInt8] { parts.flatMap { $0 } }

    private static func cat(_ parts: [[UInt8]]) -> [UInt8] { parts.flatMap { $0 } }

    private static func bigEndian(_ value: Int, bytes: Int) -> [UInt8] {
        (0..<bytes).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }

    private static func field(_ bytes: [UInt8], _ at: Int, _ count: Int) throws -> Int {
        guard at >= 0, count <= 8, at + count <= bytes.count else { throw Failure.unsupportedFile }
        return bytes[at..<(at + count)].reduce(0) { $0 << 8 | Int($1) }
    }

    private static func read(_ handle: FileHandle, from offset: Int, count: Int) throws -> [UInt8] {
        try handle.seek(toOffset: UInt64(offset))
        guard let data = try handle.read(upToCount: count), data.count == count else { throw Failure.unsupportedFile }
        return [UInt8](data)
    }

    /// Copies `start..<end` of `handle` into `output` in pieces, so long videos never load whole.
    private static func copy(_ handle: FileHandle, from start: Int, to end: Int, into output: FileHandle) throws {
        try handle.seek(toOffset: UInt64(start))
        var position = start
        while position < end {
            guard let data = try handle.read(upToCount: min(end - position, 4 << 20)), !data.isEmpty else {
                throw Failure.unsupportedFile
            }
            try output.write(contentsOf: data)
            position += data.count
        }
    }

    private static func writeFile(_ url: URL, _ body: (FileHandle) throws -> Void) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close() }
        try body(output)
        try output.synchronize()
    }
}
