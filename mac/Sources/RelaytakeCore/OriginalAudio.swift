import Foundation

// The recording's own sound normally follows the video: wherever the video is cut, the sound is cut the same
// way. Splicing with the Audio track selected breaks the sound on its own instead. From then on the sound is
// a list of parts placed on the edited timeline, and removing one leaves silence while the picture carries on.

/// One stretch of the recording's own sound, placed on the edited timeline.
public struct OriginalAudioPart: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    /// Which seconds of the original recording play.
    public var source: TimeSpan
    /// Where it starts on the edited timeline.
    public var start: Double

    public var length: Double { source.length }
    public var end: Double { start + length }
    public var span: TimeSpan { TimeSpan(start: start, end: end) }

    public init(id: UUID = UUID(), source: TimeSpan, start: Double) {
        self.id = id
        self.source = source
        self.start = start
    }
}

public extension StudioProject {
    /// Whether the sound still follows the video's cuts (the default).
    var originalAudioFollowsVideo: Bool { audioParts == nil }

    /// The recording's sound as it plays: the video's kept pieces end to end, or the parts cut on their own.
    var originalAudioParts: [OriginalAudioPart] {
        if let audioParts { return audioParts }
        var elapsed = 0.0
        return cuts.segments.map { segment in
            defer { elapsed += segment.length }
            return OriginalAudioPart(source: segment, start: elapsed)
        }
    }

    /// Breaks the recording's sound at `time` of the edited timeline without touching the video. Returns false
    /// when the spot is too close to an edge of a part.
    @discardableResult
    mutating func spliceOriginalAudio(at time: Double) -> Bool {
        var parts = originalAudioParts
        guard let index = parts.firstIndex(where: {
            time - $0.start > EditModel.minimumPart && $0.end - time > EditModel.minimumPart
        }) else { return false }
        let part = parts[index]
        let cut = part.source.start + (time - part.start)
        parts[index].source = TimeSpan(start: part.source.start, end: cut)
        parts.insert(OriginalAudioPart(source: TimeSpan(start: cut, end: part.source.end), start: time), at: index + 1)
        audioParts = parts
        return true
    }

    /// Breaks the video at `time` and leaves the sound whole: the sound stops following the video's cuts, so
    /// it plays on unbroken across the new splice.
    @discardableResult
    mutating func spliceVideoOnly(at time: Double) -> Bool {
        let sound = originalAudioParts
        guard cuts.splice(atOutput: time) else { return false }
        audioParts = sound
        return true
    }

    /// Breaks every track at `time`: the video and the recording's sound (which, if it already has cuts of its
    /// own, is cut there too). Returns false when neither could be cut there.
    @discardableResult
    mutating func spliceAllTracks(at time: Double) -> Bool {
        let video = cuts.splice(atOutput: time)
        let sound = audioParts == nil ? false : spliceOriginalAudio(at: time)
        return video || sound
    }

    /// Takes one part of the sound out, leaving silence. The video and everything else stays where it is.
    @discardableResult
    mutating func removeOriginalAudioPart(_ id: UUID) -> Bool {
        var parts = originalAudioParts
        guard let index = parts.firstIndex(where: { $0.id == id }) else { return false }
        parts.remove(at: index)
        audioParts = parts
        return true
    }

    /// Whether the break after sound part `index` is a plain splice (the parts touch, on the timeline and in the
    /// recording), as opposed to a gap where sound was taken out.
    func isOriginalAudioSplice(afterPart index: Int) -> Bool {
        let parts = originalAudioParts
        guard parts.indices.contains(index), parts.indices.contains(index + 1) else { return false }
        return abs(parts[index].end - parts[index + 1].start) < 1e-6
            && abs(parts[index].source.end - parts[index + 1].source.start) < 1e-6
    }

    /// Joins two parts of the sound that were only spliced, undoing the break.
    @discardableResult
    mutating func removeOriginalAudioSplice(afterPart index: Int) -> Bool {
        guard isOriginalAudioSplice(afterPart: index) else { return false }
        var parts = originalAudioParts
        parts[index].source.end = parts[index + 1].source.end
        parts.remove(at: index + 1)
        audioParts = parts
        return true
    }

    /// Makes the sound follow the video's cuts again, forgetting any cuts made to it alone.
    mutating func relinkOriginalAudio() { audioParts = nil }

    func originalAudioPart(_ id: UUID) -> OriginalAudioPart? { audioParts?.first { $0.id == id } }

    /// The recording's sound parts after `range` of the edited timeline was removed: the parts either side keep
    /// lining up with the picture they were recorded against.
    internal func originalAudioParts(removing range: TimeSpan) -> [OriginalAudioPart]? {
        guard let audioParts else { return nil }
        let removed = range.length
        var rebuilt: [OriginalAudioPart] = []
        for part in audioParts {
            if part.end <= range.start {
                rebuilt.append(part)
            } else if part.start >= range.end {
                var moved = part
                moved.start -= removed
                rebuilt.append(moved)
            } else {
                if range.start - part.start >= Self.minimumAudioPart {
                    var before = part
                    before.source.end = part.source.start + (range.start - part.start)
                    rebuilt.append(before)
                }
                if part.end - range.end >= Self.minimumAudioPart {
                    let skipped = range.end - part.start
                    rebuilt.append(OriginalAudioPart(
                        source: TimeSpan(start: part.source.start + max(0, skipped), end: part.source.end),
                        start: range.start))
                }
            }
        }
        return rebuilt
    }

    /// The recording's sound parts after `length` seconds of footage were put back at `position`: later parts
    /// move later and a part that spans the spot is split around the new footage, which has no sound of its own.
    internal func originalAudioParts(inserting length: Double, at position: Double) -> [OriginalAudioPart]? {
        guard let audioParts else { return nil }
        var rebuilt: [OriginalAudioPart] = []
        for part in audioParts {
            if part.end <= position {
                rebuilt.append(part)
            } else if part.start >= position {
                var moved = part
                moved.start += length
                rebuilt.append(moved)
            } else {
                var before = part
                before.source.end = part.source.start + (position - part.start)
                rebuilt.append(before)
                rebuilt.append(OriginalAudioPart(
                    source: TimeSpan(start: before.source.end, end: part.source.end), start: position + length))
            }
        }
        return rebuilt
    }

    /// Keeps the sound parts inside the edited video.
    internal func clampedOriginalAudioParts(_ parts: [OriginalAudioPart]?) -> [OriginalAudioPart]? {
        guard let parts else { return nil }
        let total = outputDuration
        return parts.compactMap { part in
            guard part.start < total - 0.01 else { return nil }
            var part = part
            if part.end > total { part.source.end = part.source.start + (total - part.start) }
            return part.length >= Self.minimumAudioPart ? part : nil
        }
    }

    internal static var minimumAudioPart: Double { 0.05 }
}
