import Foundation

public struct TimeSpan: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var length: TimeInterval { end - start }

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }
}

public enum EditError: LocalizedError, Equatable {
    case invalidRange
    case nothingLeft

    public var errorDescription: String? {
        switch self {
        case .invalidRange: "Select a valid time range."
        case .nothingLeft: "Keep at least a moment of the recording."
        }
    }
}

/// Non-destructive cut list in source-video time, mirroring the browser extension's editor.
/// `segments` are the parts that will be kept, in order. Undo and reset never touch the file.
public struct EditModel: Equatable, Sendable {
    public let duration: TimeInterval
    public private(set) var segments: [TimeSpan]
    private var history: [[TimeSpan]] = []

    public static let minimumSegment: TimeInterval = 0.05
    public static let minimumResult: TimeInterval = 0.1

    public init(duration: TimeInterval) {
        self.duration = max(0, duration)
        self.segments = [TimeSpan(start: 0, end: max(0, duration))]
    }

    public var keptDuration: TimeInterval { segments.reduce(0) { $0 + $1.length } }
    public var isEdited: Bool { segments != [TimeSpan(start: 0, end: duration)] }
    public var canUndo: Bool { !history.isEmpty }

    /// Keep only the selected range (still respecting earlier cuts).
    public mutating func trim(to range: TimeSpan) throws { try apply(range, keep: true) }

    /// Remove the selected range and join what is left.
    public mutating func remove(_ range: TimeSpan) throws { try apply(range, keep: false) }

    public mutating func undo() {
        if let previous = history.popLast() { segments = previous }
    }

    public mutating func reset() {
        if isEdited { history.append(segments) }
        segments = [TimeSpan(start: 0, end: duration)]
    }

    /// Source time → time in the edited output, or nil when the moment was cut out.
    public func outputTime(forSource time: TimeInterval) -> TimeInterval? {
        var elapsed: TimeInterval = 0
        for segment in segments {
            if time >= segment.start && time <= segment.end { return elapsed + (time - segment.start) }
            elapsed += segment.length
        }
        return nil
    }

    private mutating func apply(_ range: TimeSpan, keep: Bool) throws {
        guard range.start.isFinite, range.end.isFinite, range.start >= 0, range.end > range.start else {
            throw EditError.invalidRange
        }
        let next = segments.flatMap { segment -> [TimeSpan] in
            if keep {
                return [TimeSpan(start: max(segment.start, range.start), end: min(segment.end, range.end))]
            }
            return [
                TimeSpan(start: segment.start, end: min(segment.end, range.start)),
                TimeSpan(start: max(segment.start, range.end), end: segment.end),
            ]
        }.filter { $0.length >= Self.minimumSegment }
        guard next.reduce(0, { $0 + $1.length }) >= Self.minimumResult else { throw EditError.nothingLeft }
        history.append(segments)
        segments = next
    }
}

/// Splices: breaks in the video, with parts between them. A break by itself removes nothing; the parts
/// on either side stay joined end to end. Removing a part leaves a gap in the original, and the edges
/// next to the gap can be dragged back out to bring that footage back.
public enum CutEdge: Sendable { case start, end }

public extension EditModel {
    /// A part this short or shorter cannot be made by splicing, so a stray click cannot leave a sliver.
    static let minimumPart: TimeInterval = 0.2

    /// The edited video's parts, in order, as spans of the edited timeline.
    var partSpans: [TimeSpan] {
        var elapsed = 0.0
        return segments.map { segment in
            defer { elapsed += segment.length }
            return TimeSpan(start: elapsed, end: elapsed + segment.length)
        }
    }

    /// Which part plays at `output` seconds of the edited video.
    func partIndex(atOutput output: TimeInterval) -> Int? {
        let spans = partSpans
        if let index = spans.firstIndex(where: { output >= $0.start && output < $0.end }) { return index }
        return output >= (spans.last?.end ?? 0) ? spans.indices.last : nil
    }

    /// Whether the break after part `index` is a plain splice (the parts touch in the original), as opposed
    /// to a gap where something was removed.
    func isSplice(afterPart index: Int) -> Bool {
        segments.indices.contains(index) && segments.indices.contains(index + 1)
            && abs(segments[index].end - segments[index + 1].start) < 1e-6
    }

    /// Breaks the part under `output` in two. Returns false when the spot is too close to an edge.
    @discardableResult
    mutating func splice(atOutput output: TimeInterval) -> Bool {
        var elapsed = 0.0
        for (index, segment) in segments.enumerated() {
            let into = output - elapsed
            if into > Self.minimumPart, into < segment.length - Self.minimumPart {
                let cut = segment.start + into
                segments[index] = TimeSpan(start: segment.start, end: cut)
                segments.insert(TimeSpan(start: cut, end: segment.end), at: index + 1)
                return true
            }
            elapsed += segment.length
        }
        return false
    }

    /// Joins two parts that were only spliced, undoing the break.
    @discardableResult
    mutating func removeSplice(afterPart index: Int) -> Bool {
        guard isSplice(afterPart: index) else { return false }
        segments[index] = TimeSpan(start: segments[index].start, end: segments[index + 1].end)
        segments.remove(at: index + 1)
        return true
    }

    /// Slides a plain splice to another moment of the original: one part gets longer and its neighbor
    /// shorter, so the edited video keeps its length. Returns the source time it settled on.
    @discardableResult
    mutating func slideSplice(afterPart index: Int, toSource time: TimeInterval) -> TimeInterval? {
        guard isSplice(afterPart: index) else { return nil }
        let low = segments[index].start + Self.minimumPart
        let high = segments[index + 1].end - Self.minimumPart
        guard low <= high else { return nil }
        let settled = min(max(time, low), high)
        segments[index].end = settled
        segments[index + 1].start = settled
        return settled
    }

    /// Moves one edge of a part to another moment of the original, never past a neighboring part or
    /// the ends of the original. Returns where that edge is in the edited video before the change, and
    /// how much longer (or shorter, if negative) the part became; nil if nothing changed.
    mutating func moveEdge(ofPart index: Int, edge: CutEdge, toSource time: TimeInterval) -> (anchor: TimeInterval, growth: TimeInterval)? {
        guard segments.indices.contains(index) else { return nil }
        let segment = segments[index]
        let spans = partSpans
        switch edge {
        case .start:
            let low = index > 0 ? segments[index - 1].end : 0
            let high = segment.end - Self.minimumPart
            guard low <= high else { return nil }
            let settled = min(max(time, low), high)
            guard abs(settled - segment.start) > 1e-9 else { return nil }
            segments[index].start = settled
            return (spans[index].start, segment.start - settled)
        case .end:
            let low = segment.start + Self.minimumPart
            let high = index < segments.count - 1 ? segments[index + 1].start : duration
            guard low <= high else { return nil }
            let settled = min(max(time, low), high)
            guard abs(settled - segment.end) > 1e-9 else { return nil }
            segments[index].end = settled
            return (spans[index].end, settled - segment.end)
        }
    }
}

public func timeLabel(_ seconds: TimeInterval) -> String {
    let total = max(0, seconds)
    return String(format: "%02d:%04.1f", Int(total) / 60, total.truncatingRemainder(dividingBy: 60))
}
