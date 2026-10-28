import Foundation

// The Studio saves where the user is as they work, so a crash, a force quit or closing the app never costs
// them their edits. The draft sits in a hidden folder beside the take, and only ever holds the edit
// decisions (cuts, text, zooms, audio clips, camera, captions) and the playhead. Never the media itself.

/// Everything about a Studio session that is worth coming back to.
public struct StudioDraft: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version = StudioDraft.currentVersion
    public var savedAt = Date()
    /// Length of the original when the draft was made. A draft is dropped if the original has since changed.
    public var sourceDuration: Double
    public var segments: [TimeSpan]
    public var texts: [TextOverlay]
    public var captions: StudioCaptions?
    public var zooms: [ZoomSegment]
    public var background: WindowBackground?
    public var clips: [AudioClip]
    public var originalVolume: Double
    /// The recording's sound when it was cut apart from the video; nil while it follows the video.
    public var audioParts: [OriginalAudioPart]?
    public var camera: CameraBubble
    /// Playhead, in seconds of the edited video.
    public var playhead: Double
    /// Which saved version of a shared `.hottake` file this edit continues from, if it came from one.
    public var sharedRevision: Int?

    public init(project: StudioProject, playhead: Double, savedAt: Date = Date()) {
        self.savedAt = savedAt
        sourceDuration = project.cuts.duration
        segments = project.cuts.segments
        texts = project.texts
        captions = project.captions
        zooms = project.zooms
        background = project.background
        clips = project.clips
        originalVolume = project.originalVolume
        audioParts = project.audioParts
        camera = project.camera
        self.playhead = playhead
    }

    /// The project this draft describes, or nil when it no longer fits the recording. Audio files that have
    /// gone missing are left out rather than failing the whole draft.
    public func project(duration: Double, cameraSource: CameraSource?, fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> StudioProject? {
        guard version == Self.currentVersion, abs(sourceDuration - duration) < 0.5 else { return nil }
        var project = StudioProject(duration: duration, cameraSource: cameraSource)
        project.cuts = EditModel(duration: duration, segments: segments)
        project.texts = texts
        project.captions = captions
        project.zooms = zooms
        project.background = background
        project.clips = clips.filter { fileExists($0.url) }
        project.originalVolume = min(1, max(0, originalVolume))
        project.audioParts = project.clampedOriginalAudioParts(audioParts)
        // Without the camera video there is nothing for the bubble settings to apply to.
        if cameraSource != nil { project.camera = camera }
        return project
    }
}

/// Reads and writes the draft for one take. Writes are atomic: a draft is either the old one or the new one.
public struct StudioDraftStore: Sendable {
    public let url: URL

    public init(files: TakeFiles) {
        url = files.draft
    }

    public func encode(_ draft: StudioDraft) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(draft)
    }

    @discardableResult
    public func write(_ data: Data) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch { return false }
    }

    public func load() -> StudioDraft? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StudioDraft.self, from: data)
    }

    /// Removes the draft, and the folder too once it is empty.
    public func discard() {
        try? FileManager.default.removeItem(at: url)
        let folder = url.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
