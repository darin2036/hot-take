import Foundation

/// File layout for one take. Everything sits beside the video so the folder stays portable:
/// `Name.mp4`, `Name.vtt` (captions), `Name.json` (title, summary, transcript).
public struct TakeFiles: Equatable, Sendable {
    public let directory: URL
    public let baseName: String

    public init(directory: URL, baseName: String) {
        self.directory = directory
        self.baseName = baseName
    }

    public var video: URL { directory.appendingPathComponent(baseName).appendingPathExtension("mp4") }
    public var captions: URL { directory.appendingPathComponent(baseName).appendingPathExtension("vtt") }
    public var metadata: URL { directory.appendingPathComponent(baseName).appendingPathExtension("json") }

    /// A take recorded with a camera keeps what it was made from here, out of sight: the screen video on its
    /// own and the camera video. The take's own `.mp4` has the camera already drawn in.
    /// A numbered piece of a take that was paused. Pieces wait in the staging folder until the take is joined.
    public func pieceURL(number: Int, extension ext: String) -> URL {
        directory.appendingPathComponent(".relaytake-processing", isDirectory: true)
            .appendingPathComponent("\(baseName).piece-\(number).\(ext)")
    }

    /// Where the Studio keeps the draft of an unfinished edit, out of sight beside the take.
    public var draftsDirectory: URL { directory.appendingPathComponent(".hot-take-drafts", isDirectory: true) }
    public var draft: URL { draftsDirectory.appendingPathComponent(baseName + ".studio.json") }
    public var originalsDirectory: URL { directory.appendingPathComponent(".hot-take-originals", isDirectory: true) }
    /// Audio that came with a shared take (music, voiceovers), kept out of sight beside it.
    public var audioDirectory: URL { directory.appendingPathComponent(".hot-take-audio", isDirectory: true) }
    public func audioFile(number: Int, extension ext: String) -> URL {
        audioDirectory.appendingPathComponent("\(baseName).\(number).\(ext)")
    }
    /// Every audio file kept for this take.
    public func audioFiles(fileManager: FileManager = .default) -> [URL] {
        let names = (try? fileManager.contentsOfDirectory(atPath: audioDirectory.path)) ?? []
        return names.filter { $0.hasPrefix(baseName + ".") }.map { audioDirectory.appendingPathComponent($0) }
    }
    /// The take turned into a request for a coding agent (`PROMPT.md` and its pictures), out of sight beside it.
    public var agentDirectory: URL {
        directory.appendingPathComponent(".hot-take-agent", isDirectory: true).appendingPathComponent(baseName, isDirectory: true)
    }
    public var screenOriginal: URL { originalsDirectory.appendingPathComponent(baseName + ".screen.mp4") }
    public var cameraOriginal: URL { originalsDirectory.appendingPathComponent(baseName + ".camera.mov") }

    /// `~/Movies/Hot Take`. A Mac that already has recordings in the folder from an earlier version
    /// (`~/Movies/Relaytake`) keeps using it, so nothing moves and no recording is left behind.
    public static func defaultDirectory(movies: URL? = nil, fileManager: FileManager = .default) -> URL {
        let base = movies ?? fileManager.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        let current = base.appendingPathComponent("Hot Take", isDirectory: true)
        let legacy = base.appendingPathComponent("Relaytake", isDirectory: true)
        if !fileManager.fileExists(atPath: current.path), fileManager.fileExists(atPath: legacy.path) { return legacy }
        return current
    }

    /// "Hot Take 2026-10-21 at 09.30.15". Uses dots, not colons, so file managers and cloud-sync tools accept it.
    public static func baseName(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "Hot Take %04d-%02d-%02d at %02d.%02d.%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}

public struct TakeMetadata: Codable, Equatable, Sendable {
    public var title: String
    public var summary: String
    public var created: Date
    public var durationSeconds: Double?
    public var transcript: [CaptionSegment]
    /// Free-form labels the user adds in the Info tab.
    public var tags: [String]
    public var notes: String
    /// Mouse clicks seen while recording, so the Studio can propose zooms. Empty for older recordings.
    public var clicks: [ClickEvent]
    /// What was recorded: "screen", "window" or "area". Nil for older recordings.
    public var captureKind: String?
    /// For a copy saved from the Studio, the file name (without extension) of the recording it was made
    /// from, in the same folder. The library nests copies under their original with it.
    public var derivedFrom: String?
    /// Seconds after the screen recording began that the camera recording began. Nil when no camera was used.
    public var cameraOffset: Double?
    /// Where the presenter bubble was placed while recording. Nil means the default corner.
    public var cameraPlacement: CameraPlacement?
    /// The moment (seconds into the video) chosen as the picture shown for this take in the library. Nil
    /// uses the opening of the video.
    public var thumbnailTime: Double?
    /// The transcript translated on this Mac, keyed by language identifier ("es", "fr", "ja"). Each one has the
    /// same lines and timing as `transcript`; it is dropped whenever the transcript changes. Empty when none.
    public var translations: [String: [CaptionSegment]]
    /// The parts of the recording: suggested from the transcript, then kept, renamed, moved or removed by the person.
    /// Times are seconds into this take's video, so a copy with parts cut out does not carry them. Empty when none.
    public var chapters: [Chapter]
    /// Whether this recording's transcript shows chapters. Nil follows the app-wide default; set when the person turns
    /// them on or off for this recording (or removes every chapter). Turning them off keeps the saved chapters.
    public var chaptersEnabled: Bool?

    public init(
        title: String, summary: String, created: Date, durationSeconds: Double? = nil,
        transcript: [CaptionSegment] = [], tags: [String] = [], notes: String = "",
        clicks: [ClickEvent] = [], captureKind: String? = nil, derivedFrom: String? = nil, cameraOffset: Double? = nil,
        cameraPlacement: CameraPlacement? = nil, thumbnailTime: Double? = nil,
        translations: [String: [CaptionSegment]] = [:], chapters: [Chapter] = [], chaptersEnabled: Bool? = nil
    ) {
        self.title = title
        self.summary = summary
        self.created = created
        self.durationSeconds = durationSeconds
        self.transcript = transcript
        self.tags = tags
        self.notes = notes
        self.clicks = clicks
        self.captureKind = captureKind
        self.derivedFrom = derivedFrom
        self.cameraOffset = cameraOffset
        self.cameraPlacement = cameraPlacement
        self.thumbnailTime = thumbnailTime
        self.translations = translations
        self.chapters = chapters
        self.chaptersEnabled = chaptersEnabled
    }

    /// Older sidecars have no tags or notes; they decode with empty values.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        created = try c.decode(Date.self, forKey: .created)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds)
        transcript = try c.decodeIfPresent([CaptionSegment].self, forKey: .transcript) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        clicks = try c.decodeIfPresent([ClickEvent].self, forKey: .clicks) ?? []
        captureKind = try c.decodeIfPresent(String.self, forKey: .captureKind)
        derivedFrom = try c.decodeIfPresent(String.self, forKey: .derivedFrom)
        cameraOffset = try c.decodeIfPresent(Double.self, forKey: .cameraOffset)
        cameraPlacement = try c.decodeIfPresent(CameraPlacement.self, forKey: .cameraPlacement)
        thumbnailTime = try c.decodeIfPresent(Double.self, forKey: .thumbnailTime)
        translations = try c.decodeIfPresent([String: [CaptionSegment]].self, forKey: .translations) ?? [:]
        chapters = try c.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
        chaptersEnabled = try c.decodeIfPresent(Bool.self, forKey: .chaptersEnabled)
    }

    /// Keeps what was seen while recording (clicks, what was captured) on a take whose metadata is being
    /// rewritten from scratch.
    public mutating func keepCapture(of existing: TakeMetadata) {
        clicks = existing.clicks
        captureKind = existing.captureKind
        derivedFrom = existing.derivedFrom
        cameraOffset = existing.cameraOffset
        cameraPlacement = existing.cameraPlacement
        thumbnailTime = existing.thumbnailTime
    }

    /// "demo, bug report,  Demo" → ["demo", "bug report"]: trimmed, de-duplicated ignoring case.
    public static func parseTags(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> TakeMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TakeMetadata.self, from: data)
    }
}

public enum SummaryPrompt {
    /// The on-device model has a small context window, so keep the start and end of long talks.
    public static let maxCharacters = 9000

    public static func clipped(_ transcript: String) -> String {
        guard transcript.count > maxCharacters else { return transcript }
        let half = maxCharacters / 2
        return String(transcript.prefix(half)) + "\n[…middle of recording omitted…]\n" + String(transcript.suffix(half))
    }

    public static let instructions = """
        You write short titles and summaries for screen recordings used in team walkthroughs, \
        demos, and bug reports. Use only what the transcript says. Do not invent details. \
        Reply in exactly this format and nothing else:
        TITLE: <specific title, at most eight words, no quotes, no trailing period>
        SUMMARY: <two or three plain sentences saying what the recording shows or decides>
        """

    public static func prompt(transcript: String) -> String {
        "Transcript of a screen recording:\n\n\(clipped(transcript))"
    }

    /// Reads the TITLE:/SUMMARY: reply. If the model ignores the format, the whole reply becomes
    /// the summary and the title stays empty so the caller can keep its default.
    public static func parse(_ reply: String) -> (title: String, summary: String) {
        var title = ""
        var summaryLines: [String] = []
        var inSummary = false
        for line in reply.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let value = value(of: "TITLE:", in: trimmed) {
                title = cleanedTitle(value)
                inSummary = false
            } else if let value = value(of: "SUMMARY:", in: trimmed) {
                summaryLines = [value]
                inSummary = true
            } else if inSummary {
                summaryLines.append(trimmed)
            }
        }
        var summary = summaryLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty && summary.isEmpty {
            summary = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (title, summary)
    }

    private static func value(of label: String, in line: String) -> String? {
        guard line.uppercased().hasPrefix(label) else { return nil }
        return String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
    }

    /// Models sometimes wrap titles in quotes or end them with a period.
    public static func cleanedTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'"))
        while title.hasSuffix(".") { title.removeLast() }
        return String(title.prefix(80))
    }
}
