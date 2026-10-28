import Foundation

// The Studio edits one recording as a small project: cuts to the picture, text on top, and extra
// audio (background music, a voiceover). Everything except the cuts lives on the *output* timeline,
// the video as it will be after the cuts, so a cut ripples through text and voiceover the way it
// does in a video editor and they stay attached to the picture. All rules here are pure and tested.

/// A color for text or the box behind it. Components are 0...1.
public struct TextColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    public static let white = TextColor(red: 1, green: 1, blue: 1)
    public static let black = TextColor(red: 0, green: 0, blue: 0)

    /// The swatches offered in the Studio; any other color can be chosen with the color picker.
    public static let presets: [(name: String, color: TextColor)] = [
        ("White", .white), ("Yellow", TextColor(red: 1, green: 0.84, blue: 0.1)),
        ("Orange", TextColor(red: 1, green: 0.6, blue: 0.1)), ("Red", TextColor(red: 1, green: 0.27, blue: 0.23)),
        ("Pink", TextColor(red: 1, green: 0.45, blue: 0.75)), ("Green", TextColor(red: 0.3, green: 0.85, blue: 0.4)),
        ("Blue", TextColor(red: 0.25, green: 0.55, blue: 1)), ("Purple", TextColor(red: 0.65, green: 0.4, blue: 0.95)),
        ("Black", .black),
    ]
}

public struct TextOverlay: Codable, Identifiable, Equatable, Sendable {
    /// Quick sizes. The size itself is continuous (`heightFraction`), so any size in between works too.
    public enum Size: String, CaseIterable, Sendable {
        case small, medium, large, huge
        /// Text height as a fraction of the video's height, so it looks the same at any resolution.
        public var heightFraction: Double {
            switch self {
            case .small: 0.05
            case .medium: 0.075
            case .large: 0.11
            case .huge: 0.16
            }
        }
        public var title: String {
            switch self {
            case .small: "S"
            case .medium: "M"
            case .large: "L"
            case .huge: "XL"
            }
        }
    }

    public static let sizeRange = 0.03...0.2
    public static let systemFont = "System"

    public let id: UUID
    public var text: String
    /// Output-timeline seconds.
    public var start: Double
    public var end: Double
    /// Center of the text, 0...1 from the left and from the top of the picture.
    public var x: Double
    public var y: Double
    /// "System" or the name of an installed font family.
    public var fontFamily: String
    public var isBold: Bool
    public var isItalic: Bool
    public var heightFraction: Double
    public var color: TextColor
    /// A rounded box behind the text so it reads on any picture.
    public var showsBackground: Bool
    public var boxColor: TextColor
    /// Whether the text fades in and out. Captions switch instantly so one line never overlaps the next.
    public var fades = true

    public var length: Double { end - start }

    /// The same text with a new identity, for splitting one into two.
    func copy(withID id: UUID) -> TextOverlay {
        var copy = TextOverlay(id: id, text: text, start: start, end: end, x: x, y: y, size: .medium,
            fontFamily: fontFamily, isBold: isBold, isItalic: isItalic, color: color,
            showsBackground: showsBackground, boxColor: boxColor)
        copy.heightFraction = heightFraction
        copy.fades = fades
        return copy
    }

    /// The quick size this is exactly, if any.
    public var sizePreset: Size? { Size.allCases.first { abs($0.heightFraction - heightFraction) < 0.0005 } }

    public init(
        id: UUID = UUID(), text: String = "Your text", start: Double, end: Double, x: Double = 0.5, y: Double = 0.82,
        size: Size = .medium, fontFamily: String = TextOverlay.systemFont, isBold: Bool = true, isItalic: Bool = false,
        color: TextColor = .white, showsBackground: Bool = true, boxColor: TextColor = .black
    ) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
        self.x = x
        self.y = y
        self.fontFamily = fontFamily
        self.isBold = isBold
        self.isItalic = isItalic
        self.heightFraction = size.heightFraction
        self.color = color
        self.showsBackground = showsBackground
        self.boxColor = boxColor
    }
}

/// One stretch of extra audio. Music usually fits the video; a voiceover is a recorded take.
public struct AudioClip: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case music, voiceover
    }

    /// A contiguous piece of the file to place on the output timeline.
    public struct Piece: Equatable, Sendable {
        public var outputStart: Double
        public var sourceStart: Double
        public var length: Double
    }

    public struct Ramp: Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var from: Double
        public var to: Double
    }

    public let id: UUID
    public var kind: Kind
    public var url: URL
    public var name: String
    /// Length of the file.
    public var sourceDuration: Double
    /// Where in the file playback begins (a clip split by a cut continues from the right place).
    public var sourceStart: Double
    /// Output-timeline seconds.
    public var start: Double
    public var length: Double
    public var volume: Double
    public var fadeIn: Double
    public var fadeOut: Double
    /// Stretch to the end of the video, however long it is.
    public var fitsVideo: Bool
    /// Repeat the file when it is shorter than the space it fills.
    public var loops: Bool

    public init(
        id: UUID = UUID(), kind: Kind, url: URL, name: String, sourceDuration: Double, sourceStart: Double = 0,
        start: Double = 0, length: Double, volume: Double = 1, fadeIn: Double = 0, fadeOut: Double = 0,
        fitsVideo: Bool = false, loops: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.name = name
        self.sourceDuration = sourceDuration
        self.sourceStart = sourceStart
        self.start = start
        self.length = length
        self.volume = volume
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.fitsVideo = fitsVideo
        self.loops = loops
    }

    /// How long it actually plays given the video's length.
    public func effectiveLength(outputDuration: Double) -> Double {
        let available = max(0, outputDuration - start)
        return fitsVideo ? available : min(length, available)
    }

    /// The file pieces to lay down, repeating the file if `loops` and it is too short.
    public func pieces(outputDuration: Double) -> [Piece] {
        let playing = effectiveLength(outputDuration: outputDuration)
        guard playing > 0.001, sourceDuration > 0.001, sourceStart < sourceDuration - 0.001 else { return [] }
        var result: [Piece] = []
        var cursor = start
        var source = max(0, sourceStart)
        let end = start + playing
        while cursor < end - 0.001 {
            let take = min(sourceDuration - source, end - cursor)
            result.append(Piece(outputStart: cursor, sourceStart: source, length: take))
            cursor += take
            guard loops else { break }
            source = 0
        }
        return result
    }

    /// Volume changes over time: a fade in at the start and a fade out at the end.
    public func ramps(outputDuration: Double) -> [Ramp] {
        let playing = effectiveLength(outputDuration: outputDuration)
        guard playing > 0.001 else { return [] }
        let fadeIn = min(self.fadeIn, playing / 2)
        let fadeOut = min(self.fadeOut, playing / 2)
        var ramps: [Ramp] = []
        if fadeIn > 0.001 { ramps.append(Ramp(start: start, end: start + fadeIn, from: 0, to: volume)) }
        if fadeOut > 0.001 {
            ramps.append(Ramp(start: start + playing - fadeOut, end: start + playing, from: volume, to: 0))
        }
        return ramps
    }
}

public extension EditModel {
    /// The source moment that plays at `output` seconds of the edited video.
    func sourceTime(forOutput output: Double) -> Double? {
        var elapsed = 0.0
        for segment in segments {
            if output >= elapsed && output <= elapsed + segment.length { return segment.start + (output - elapsed) }
            elapsed += segment.length
        }
        return nil
    }

    /// The pieces of the original that play during `range` of the edited video. More than one when
    /// the range crosses an earlier cut.
    func sourceSpans(forOutput range: TimeSpan) -> [TimeSpan] {
        var result: [TimeSpan] = []
        var offset = 0.0
        for segment in segments {
            let low = max(range.start, offset)
            let high = min(range.end, offset + segment.length)
            if high > low {
                result.append(TimeSpan(start: segment.start + (low - offset), end: segment.start + (high - offset)))
            }
            offset += segment.length
        }
        return result
    }

    /// Where the kept pieces join, as output-timeline seconds (for drawing cut marks).
    var joins: [Double] {
        var elapsed = 0.0
        return segments.dropLast().map { segment in
            elapsed += segment.length
            return elapsed
        }
    }
}

public struct StudioProject: Equatable, Sendable {
    public var cuts: EditModel
    public var texts: [TextOverlay] = []
    /// Captions drawn into the picture, or nil for none. Their text and timing come from the transcript.
    public var captions: StudioCaptions?
    /// Zoom moments on the edited timeline, and the backdrop behind a window recording. Both are drawn
    /// into the picture when it is previewed or saved.
    public var zooms: [ZoomSegment] = []
    public var background: WindowBackground?
    /// Arrows, boxes and blurred regions on the recorded picture, and rings at the recorded clicks (see
    /// `StudioAnnotations.swift`). Drawn into the picture, under the text, and zoomed with it.
    public var shapes: [ShapeOverlay] = []
    public var clickHighlight: ClickHighlight?
    public var clips: [AudioClip] = []
    /// Volume of the recording's own sound. 0 mutes it (for a full redub).
    public var originalVolume: Double = 1
    /// The recording's sound cut on its own, or nil while it follows the video's cuts (see `OriginalAudio.swift`).
    public var audioParts: [OriginalAudioPart]?

    /// The camera video recorded with this take, if any (fixed for the project), and how it is drawn.
    public let cameraSource: CameraSource?
    public var camera = CameraBubble()

    public static let minimumLength = 0.3
    private let sourceDuration: Double

    public init(duration: Double, cameraSource: CameraSource? = nil) {
        sourceDuration = max(0, duration)
        cuts = EditModel(duration: duration)
        self.cameraSource = cameraSource
        if let placement = cameraSource?.placement {
            camera.move(toX: placement.x, y: placement.y)
            camera.size = placement.size
            camera.clamp()
        }
    }

    public var outputDuration: Double { cuts.keptDuration }
    public var isEdited: Bool { self != StudioProject(duration: sourceDuration, cameraSource: cameraSource) }

    // MARK: Cuts (ranges are on the edited timeline)

    /// Removes a range of the edited video and ripples text and voiceover so they stay with the picture.
    public mutating func remove(_ range: TimeSpan) throws {
        let range = TimeSpan(start: max(0, range.start), end: min(outputDuration, range.end))
        guard range.length >= EditModel.minimumSegment else { throw EditError.invalidRange }
        var next = cuts
        for span in cuts.sourceSpans(forOutput: range) { try next.remove(span) }
        cuts = next
        ripple(removing: range)
    }

    /// Keeps only a range of the edited video.
    public mutating func keepOnly(_ range: TimeSpan) throws {
        let total = outputDuration
        let range = TimeSpan(start: max(0, range.start), end: min(total, range.end))
        guard range.length >= EditModel.minimumResult else { throw EditError.nothingLeft }
        var copy = self
        if range.end < total - 0.001 { try copy.remove(TimeSpan(start: range.end, end: total)) }
        if range.start > 0.001 { try copy.remove(TimeSpan(start: 0, end: range.start)) }
        self = copy
    }

    // MARK: Splices and edges

    /// Puts a break in the video at `time` of the edited timeline. Nothing is removed.
    @discardableResult
    public mutating func splice(at time: Double) -> Bool { cuts.splice(atOutput: time) }

    /// Moves the edge of a part. Pulling an edge in removes footage, and everything after it moves
    /// earlier; pulling it out brings footage back from the original (if any is left to bring back), and
    /// everything after it moves later. Text, zooms and voiceover keep their place against the picture.
    @discardableResult
    public mutating func moveEdge(ofPart index: Int, edge: CutEdge, toSource time: Double) -> Bool {
        guard let change = cuts.moveEdge(ofPart: index, edge: edge, toSource: time) else { return false }
        if change.growth < 0 {
            let removed = -change.growth
            ripple(removing: edge == .start
                ? TimeSpan(start: change.anchor, end: change.anchor + removed)
                : TimeSpan(start: change.anchor - removed, end: change.anchor))
        } else {
            ripple(inserting: change.growth, at: change.anchor)
        }
        return true
    }

    /// `[`: removes the part of the video under `time` that comes before it.
    @discardableResult
    public mutating func trimBefore(_ time: Double) -> Bool {
        guard let index = cuts.partIndex(atOutput: time) else { return false }
        let part = cuts.partSpans[index]
        guard time - part.start >= EditModel.minimumSegment else { return false }
        return (try? remove(TimeSpan(start: part.start, end: time))) != nil
    }

    /// `]`: removes the part of the video under `time` that comes after it.
    @discardableResult
    public mutating func trimAfter(_ time: Double) -> Bool {
        guard let index = cuts.partIndex(atOutput: time) else { return false }
        let part = cuts.partSpans[index]
        guard part.end - time >= EditModel.minimumSegment else { return false }
        return (try? remove(TimeSpan(start: time, end: part.end))) != nil
    }

    /// Makes room for `length` seconds of footage at `position`: later things move later, and anything
    /// that spans the spot stretches.
    private mutating func ripple(inserting length: Double, at position: Double) {
        audioParts = clampedOriginalAudioParts(originalAudioParts(inserting: length, at: position))
        texts = texts.map { text in
            var text = text
            if text.start >= position { text.start += length }
            if text.end > position { text.end += length }
            return text
        }
        zooms = zooms.map { zoom in
            var zoom = zoom
            if zoom.start >= position { zoom.start += length }
            if zoom.end > position { zoom.end += length }
            return zoom
        }
        shapes = shapes.map { shape in
            var shape = shape
            if shape.start >= position { shape.start += length }
            if shape.end > position { shape.end += length }
            return shape
        }
        clips = clips.map { clip in
            var clip = clip
            if !clip.fitsVideo, clip.start >= position { clip.start += length }
            return clip
        }
    }

    private mutating func ripple(removing range: TimeSpan) {
        audioParts = clampedOriginalAudioParts(originalAudioParts(removing: range))
        let removed = range.length
        func map(_ time: Double) -> Double {
            time <= range.start ? time : (time >= range.end ? time - removed : range.start)
        }
        texts = texts.compactMap { text in
            var text = text
            text.start = map(text.start)
            text.end = map(text.end)
            return text.length >= Self.minimumLength ? text : nil
        }
        zooms = zooms.compactMap { zoom in
            var zoom = zoom
            zoom.start = map(zoom.start)
            zoom.end = map(zoom.end)
            return zoom.length >= ZoomSegment.minimumLength ? zoom : nil
        }
        shapes = shapes.compactMap { shape in
            var shape = shape
            shape.start = map(shape.start)
            shape.end = map(shape.end)
            return shape.length >= ShapeOverlay.minimumLength ? shape : nil
        }
        var rebuilt: [AudioClip] = []
        for clip in clips {
            guard !clip.fitsVideo else { rebuilt.append(clip); continue }  // keeps playing under the cut
            let end = clip.start + clip.length
            if end <= range.start {
                rebuilt.append(clip)
            } else if clip.start >= range.end {
                var moved = clip
                moved.start -= removed
                rebuilt.append(moved)
            } else {
                // The cut lands inside this clip: keep the part before it and the part after it, so the
                // audio that remains still lines up with the picture it was recorded against.
                if clip.start < range.start - Self.minimumLength / 2 {
                    var before = clip
                    before.length = range.start - clip.start
                    before.fadeOut = 0
                    rebuilt.append(before)
                }
                if end > range.end + Self.minimumLength / 2 {
                    var after = AudioClip(
                        id: UUID(), kind: clip.kind, url: clip.url, name: clip.name, sourceDuration: clip.sourceDuration,
                        sourceStart: clip.sourceStart + (range.end - clip.start), start: range.start,
                        length: end - range.end, volume: clip.volume, fadeIn: 0, fadeOut: clip.fadeOut,
                        fitsVideo: false, loops: false)
                    after.sourceStart = min(after.sourceStart, clip.sourceDuration)
                    rebuilt.append(after)
                }
            }
        }
        clips = rebuilt.filter { $0.start < outputDuration - 0.05 }
    }

    // MARK: Text

    @discardableResult
    public mutating func addText(at time: Double, text: String = "Your text") -> UUID {
        let total = outputDuration
        let start = min(max(0, time), max(0, total - Self.minimumLength))
        let overlay = TextOverlay(text: text, start: start, end: min(total, start + 3))
        texts.append(overlay)
        return overlay.id
    }

    public mutating func updateText(_ id: UUID, _ change: (inout TextOverlay) -> Void) {
        guard let index = texts.firstIndex(where: { $0.id == id }) else { return }
        var overlay = texts[index]
        change(&overlay)
        overlay.x = min(1, max(0, overlay.x))
        overlay.y = min(1, max(0, overlay.y))
        overlay.heightFraction = min(TextOverlay.sizeRange.upperBound, max(TextOverlay.sizeRange.lowerBound, overlay.heightFraction))
        let clamped = clamp(overlay)
        texts[index] = clamped
    }

    public mutating func removeText(_ id: UUID) { texts.removeAll { $0.id == id } }

    /// Splits a text in two at `time`, both halves identical apart from timing. Returns the later half, or nil
    /// when `time` is not inside the text or would leave a half shorter than a text can be.
    @discardableResult
    public mutating func splitText(_ id: UUID, at time: Double) -> UUID? {
        guard let index = texts.firstIndex(where: { $0.id == id }) else { return nil }
        let text = texts[index]
        guard time - text.start >= Self.minimumLength, text.end - time >= Self.minimumLength else { return nil }
        var later = text.copy(withID: UUID())
        later.start = time
        texts[index].end = time
        texts.insert(later, at: index + 1)
        return later.id
    }

    /// Moves a text clip to `start`, keeping its length, within the video.
    public mutating func moveText(_ id: UUID, to start: Double) {
        let total = outputDuration  // read before mutating: the closure must not touch self
        updateText(id) { overlay in
            let length = overlay.length
            overlay.start = min(max(0, start), max(0, total - length))
            overlay.end = overlay.start + length
        }
    }

    private func clamp(_ overlay: TextOverlay) -> TextOverlay {
        var overlay = overlay
        let total = outputDuration
        overlay.start = min(max(0, overlay.start), max(0, total - Self.minimumLength))
        overlay.end = min(total, max(overlay.end, overlay.start + Self.minimumLength))
        return overlay
    }

    // MARK: Audio clips

    /// Background music, fitted to the video: starts at the beginning, loops if short, fades out.
    @discardableResult
    public mutating func addMusic(url: URL, name: String, fileDuration: Double) -> UUID {
        clips.removeAll { $0.kind == .music }  // one background track: a new song replaces the old one
        let clip = AudioClip(
            kind: .music, url: url, name: name, sourceDuration: fileDuration, start: 0, length: outputDuration,
            volume: 0.3, fadeIn: 0.5, fadeOut: 1.5, fitsVideo: true, loops: true)
        clips.append(clip)
        return clip.id
    }

    @discardableResult
    public mutating func addVoiceover(url: URL, name: String, fileDuration: Double, start: Double) -> UUID {
        let begin = min(max(0, start), outputDuration)
        let clip = AudioClip(
            kind: .voiceover, url: url, name: name, sourceDuration: fileDuration, start: begin,
            length: min(fileDuration, max(0, outputDuration - begin)), volume: 1)
        // A new take replaces any earlier voiceover it overlaps, so two voices never talk over each other.
        clips.removeAll { $0.kind == .voiceover && $0.start < clip.start + clip.length && clip.start < $0.start + $0.length }
        clips.append(clip)
        return clip.id
    }

    public mutating func updateClip(_ id: UUID, _ change: (inout AudioClip) -> Void) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        var clip = clips[index]
        change(&clip)
        clip.volume = min(1.5, max(0, clip.volume))
        clip.fadeIn = max(0, clip.fadeIn)
        clip.fadeOut = max(0, clip.fadeOut)
        clip.start = min(max(0, clip.start), max(0, outputDuration - 0.1))
        clip.length = max(0.1, min(clip.length, clip.loops ? .greatestFiniteMagnitude : clip.sourceDuration - clip.sourceStart))
        clips[index] = clip
    }

    public mutating func removeClip(_ id: UUID) { clips.removeAll { $0.id == id } }

    /// Splits an audio clip in two at `time`. The later half carries on from the same place in the file, so
    /// the sound is unbroken until one half is moved or removed. A fitted clip keeps fitting the video in the
    /// later half; the fade in stays with the first half and the fade out with the second. Returns the later
    /// half, or nil when `time` is not inside the clip or would leave a half too short.
    @discardableResult
    public mutating func splitClip(_ id: UUID, at time: Double) -> UUID? {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return nil }
        let clip = clips[index]
        let end = clip.start + clip.effectiveLength(outputDuration: outputDuration)
        guard time - clip.start >= Self.minimumLength, end - time >= Self.minimumLength else { return nil }
        // Where in the file the later half begins, allowing for a looped file that has wrapped around.
        let offset = time - clip.start
        let firstRun = max(0.001, clip.sourceDuration - clip.sourceStart)
        var source = clip.sourceStart + offset
        if clip.loops, offset >= firstRun {
            source = (offset - firstRun).truncatingRemainder(dividingBy: max(0.001, clip.sourceDuration))
        }
        guard source < clip.sourceDuration - 0.1 else { return nil }
        let later = AudioClip(
            id: UUID(), kind: clip.kind, url: clip.url, name: clip.name, sourceDuration: clip.sourceDuration,
            sourceStart: source, start: time, length: clip.fitsVideo ? outputDuration - time : end - time,
            volume: clip.volume, fadeIn: 0, fadeOut: clip.fadeOut, fitsVideo: clip.fitsVideo, loops: clip.loops)
        clips[index].length = offset
        clips[index].fitsVideo = false
        clips[index].fadeOut = 0
        clips.insert(later, at: index + 1)
        return later.id
    }

    public func clip(_ id: UUID) -> AudioClip? { clips.first { $0.id == id } }
    public func text(_ id: UUID) -> TextOverlay? { texts.first { $0.id == id } }
}

/// Snapshot-based undo and redo.
public struct UndoStack<Value: Sendable>: Sendable {
    private var past: [Value] = []
    private var future: [Value] = []

    public init() {}

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    /// Call with the value as it is *before* a change.
    public mutating func record(_ value: Value) {
        past.append(value)
        future.removeAll()
        if past.count > 100 { past.removeFirst() }
    }

    public mutating func undo(current: Value) -> Value? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        return previous
    }

    public mutating func redo(current: Value) -> Value? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        return next
    }

    public mutating func clear() {
        past = []
        future = []
    }
}

public extension TextOverlay {
    /// How visible the text is `time` seconds into the edited video: 0 before it starts, a short fade
    /// in, 1 while it shows, a short fade out, then 0.
    func opacity(at time: Double, fade: Double = 0.15) -> Double {
        guard time >= start, time <= end else { return 0 }
        let fade = max(0.001, min(fades ? fade : 0.001, length / 2))
        return min(1, (time - start) / fade, (end - time) / fade)
    }
}

public extension StudioProject {
    /// Which lane (0, 1, …) each text clip sits in so overlapping clips do not draw on top of each other.
    func textLanes() -> [UUID: Int] {
        var laneEnds: [Double] = []
        var result: [UUID: Int] = [:]
        for text in texts.sorted(by: { $0.start < $1.start }) {
            if let lane = laneEnds.firstIndex(where: { $0 <= text.start + 0.001 }) {
                laneEnds[lane] = text.end
                result[text.id] = lane
            } else {
                laneEnds.append(text.end)
                result[text.id] = laneEnds.count - 1
            }
        }
        return result
    }
}

public extension EditModel {
    /// Where a range of the *original* appears in the edited video: the parts that are still kept,
    /// as output-timeline spans (empty if all of it was cut).
    func outputSpans(forSource range: TimeSpan) -> [TimeSpan] {
        var result: [TimeSpan] = []
        var offset = 0.0
        for segment in segments {
            let low = max(range.start, segment.start)
            let high = min(range.end, segment.end)
            if high > low {
                result.append(TimeSpan(start: offset + (low - segment.start), end: offset + (high - segment.start)))
            }
            offset += segment.length
        }
        return result
    }
}
