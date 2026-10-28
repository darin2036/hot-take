import CoreGraphics
import Foundation

// Screen-recording polish done in the Studio, never at record time: a styled background around the
// window, and zoom that follows the clicks. Both live on the edited timeline like text does. All the
// geometry and timing rules here are pure and tested; the compositor only draws what they say.

/// Where the mouse was clicked, as a fraction of the recorded picture (0...1 from the top-left), and
/// when (seconds into the recording).
public struct ClickEvent: Codable, Equatable, Sendable {
    public var time: Double
    public var x: Double
    public var y: Double

    public init(time: Double, x: Double, y: Double) {
        self.time = time
        self.x = x
        self.y = y
    }
}

/// A backdrop behind the recorded window: a gradient or a solid color, with the window inset, rounded
/// and (optionally) shadowed. The output keeps the recording's size, so the window shrinks to make room.
public struct WindowBackground: Codable, Equatable, Sendable {
    public var top: TextColor
    public var bottom: TextColor
    /// Margin on each side, as a fraction of the picture's shorter side.
    public var padding: Double
    /// Corner radius, as a fraction of the window's shorter side.
    public var cornerRadius: Double
    public var shadow: Bool

    public static let paddingRange = 0.02...0.2
    public static let cornerRange = 0.0...0.08

    public init(
        top: TextColor, bottom: TextColor, padding: Double = 0.07, cornerRadius: Double = 0.03, shadow: Bool = true
    ) {
        self.top = top
        self.bottom = bottom
        self.padding = min(Self.paddingRange.upperBound, max(Self.paddingRange.lowerBound, padding))
        self.cornerRadius = min(Self.cornerRange.upperBound, max(Self.cornerRange.lowerBound, cornerRadius))
        self.shadow = shadow
    }

    public var isSolid: Bool { top == bottom }

    public struct Preset: Identifiable, Sendable {
        public var id: String { name }
        public let name: String
        public let top: TextColor
        public let bottom: TextColor
    }

    public static let presets: [Preset] = [
        Preset(name: "Sunset", top: TextColor(red: 1, green: 0.55, blue: 0.35), bottom: TextColor(red: 0.75, green: 0.2, blue: 0.6)),
        Preset(name: "Ocean", top: TextColor(red: 0.2, green: 0.6, blue: 0.95), bottom: TextColor(red: 0.15, green: 0.2, blue: 0.6)),
        Preset(name: "Mint", top: TextColor(red: 0.55, green: 0.9, blue: 0.7), bottom: TextColor(red: 0.1, green: 0.55, blue: 0.6)),
        Preset(name: "Grape", top: TextColor(red: 0.65, green: 0.45, blue: 0.95), bottom: TextColor(red: 0.3, green: 0.15, blue: 0.6)),
        Preset(name: "Slate", top: TextColor(red: 0.35, green: 0.38, blue: 0.45), bottom: TextColor(red: 0.12, green: 0.13, blue: 0.17)),
        Preset(name: "Paper", top: TextColor(red: 0.97, green: 0.96, blue: 0.93), bottom: TextColor(red: 0.85, green: 0.84, blue: 0.8)),
    ]

    public static var standard: WindowBackground {
        WindowBackground(top: presets[0].top, bottom: presets[0].bottom)
    }
}

public enum CanvasLayout {
    /// Where the recorded window sits inside the output picture (pixels, from the top-left). With no
    /// background the window fills the picture. The window keeps its aspect ratio, centered.
    public static func contentRect(canvas: CGSize, source: CGSize, background: WindowBackground?) -> CGRect {
        guard let background, canvas.width > 0, canvas.height > 0, source.width > 0, source.height > 0 else {
            return CGRect(origin: .zero, size: canvas)
        }
        let margin = background.padding * min(canvas.width, canvas.height)
        let available = CGSize(width: max(1, canvas.width - 2 * margin), height: max(1, canvas.height - 2 * margin))
        let scale = min(available.width / source.width, available.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// A point in the recorded picture (0...1) as a point in the output picture (0...1).
    public static func canvasPoint(forSource x: Double, _ y: Double, content: CGRect, canvas: CGSize) -> CGPoint {
        CGPoint(x: (content.minX + x * content.width) / canvas.width, y: (content.minY + y * content.height) / canvas.height)
    }

    /// The reverse: a point in the output picture (0...1) as a point in the recorded picture, clamped to it.
    public static func sourcePoint(forCanvas x: Double, _ y: Double, content: CGRect, canvas: CGSize) -> CGPoint {
        let sx = (x * canvas.width - content.minX) / max(1, content.width)
        let sy = (y * canvas.height - content.minY) / max(1, content.height)
        return CGPoint(x: min(1, max(0, sx)), y: min(1, max(0, sy)))
    }
}

/// A moment where the picture zooms in on one spot and then eases back out. Times are on the edited
/// timeline; the focus is a point in the recorded picture (0...1 from the top-left).
public struct ZoomSegment: Codable, Identifiable, Equatable, Sendable {
    public static let scaleRange = 1.2...4.0
    public static let minimumLength = 0.8

    public let id: UUID
    public var start: Double
    public var end: Double
    public var x: Double
    public var y: Double
    public var scale: Double

    public var length: Double { end - start }

    public init(id: UUID = UUID(), start: Double, end: Double, x: Double = 0.5, y: Double = 0.5, scale: Double = 1.8) {
        self.id = id
        self.start = start
        self.end = end
        self.x = min(1, max(0, x))
        self.y = min(1, max(0, y))
        self.scale = min(Self.scaleRange.upperBound, max(Self.scaleRange.lowerBound, scale))
    }
}

public enum ZoomCamera {
    /// Seconds to ease in, and to ease out.
    public static let ramp = 0.6

    public struct State: Equatable, Sendable {
        public var zoom: Double
        public var focusX: Double
        public var focusY: Double
    }

    public static func ease(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    /// How zoomed in the picture is at `time`, and where it is looking. Between segments it is 1× and
    /// centered; where two overlap the stronger one wins.
    public static func state(at time: Double, zooms: [ZoomSegment]) -> State {
        var best = State(zoom: 1, focusX: 0.5, focusY: 0.5)
        var bestProgress = 0.0
        for segment in zooms where time >= segment.start && time <= segment.end {
            let ramp = max(0.001, min(Self.ramp, segment.length / 2))
            let progress = ease(min((time - segment.start) / ramp, (segment.end - time) / ramp, 1))
            if progress > bestProgress {
                bestProgress = progress
                best = State(zoom: 1 + (segment.scale - 1) * progress, focusX: segment.x, focusY: segment.y)
            }
        }
        return best
    }

    /// The part of the output picture that fills the screen at this zoom (0...1, from the top-left),
    /// centered on the focus but never reaching past the edge of the picture.
    public static func crop(zoom: Double, focusX: Double, focusY: Double) -> CGRect {
        let size = 1 / max(1, zoom)
        let x = min(max(focusX - size / 2, 0), 1 - size)
        let y = min(max(focusY - size / 2, 0), 1 - size)
        return CGRect(x: x, y: y, width: size, height: size)
    }
}

public enum ZoomGenerator {
    /// Clicks close together share one zoom; clicks further apart than this start a new one.
    public static let clusterGap = 2.5

    /// Proposes zooms from recorded clicks: each group of clicks gets one zoom, centered on where they
    /// were, starting just before the first and ending shortly after the last. Clicks in cut-out parts
    /// are ignored. The result is only a starting point; every zoom can be moved, resized or removed.
    public static func segments(clicks: [ClickEvent], cuts: EditModel, scale: Double = 1.8) -> [ZoomSegment] {
        let total = cuts.keptDuration
        let placed: [(time: Double, x: Double, y: Double)] = clicks.compactMap { click in
            cuts.outputTime(forSource: click.time).map { ($0, click.x, click.y) }
        }.sorted { $0.time < $1.time }

        var groups: [[(time: Double, x: Double, y: Double)]] = []
        for click in placed {
            if let last = groups.last?.last, click.time - last.time <= clusterGap {
                groups[groups.count - 1].append(click)
            } else {
                groups.append([click])
            }
        }

        var result: [ZoomSegment] = []
        for group in groups {
            guard let first = group.first, let last = group.last else { continue }
            var start = max(0, first.time - 0.5)
            if let previous = result.last { start = max(start, previous.end) }
            var end = min(total, last.time + 1.5)
            end = max(end, min(total, start + 1.5))
            guard end - start >= ZoomSegment.minimumLength else { continue }
            let x = group.map(\.x).reduce(0, +) / Double(group.count)
            let y = group.map(\.y).reduce(0, +) / Double(group.count)
            result.append(ZoomSegment(start: start, end: end, x: x, y: y, scale: scale))
        }
        return result
    }
}

public extension StudioProject {
    func zoom(_ id: UUID) -> ZoomSegment? { zooms.first { $0.id == id } }

    /// Adds a zoom at `time` looking at the middle of the picture.
    @discardableResult
    mutating func addZoom(at time: Double, scale: Double = 1.8) -> UUID {
        let total = outputDuration
        let start = min(max(0, time), max(0, total - ZoomSegment.minimumLength))
        let segment = ZoomSegment(start: start, end: min(total, start + 2.5), scale: scale)
        zooms.append(segment)
        return segment.id
    }

    mutating func updateZoom(_ id: UUID, _ change: (inout ZoomSegment) -> Void) {
        guard let index = zooms.firstIndex(where: { $0.id == id }) else { return }
        let total = outputDuration
        var segment = zooms[index]
        change(&segment)
        segment.x = min(1, max(0, segment.x))
        segment.y = min(1, max(0, segment.y))
        segment.scale = min(ZoomSegment.scaleRange.upperBound, max(ZoomSegment.scaleRange.lowerBound, segment.scale))
        segment.start = min(max(0, segment.start), max(0, total - ZoomSegment.minimumLength))
        segment.end = min(total, max(segment.end, segment.start + ZoomSegment.minimumLength))
        zooms[index] = segment
    }

    mutating func moveZoom(_ id: UUID, to start: Double) {
        let total = outputDuration
        updateZoom(id) { segment in
            let length = segment.length
            segment.start = min(max(0, start), max(0, total - length))
            segment.end = segment.start + length
        }
    }

    mutating func removeZoom(_ id: UUID) { zooms.removeAll { $0.id == id } }

    /// Splits a zoom in two at `time` (the edited timeline). Each half keeps the same focus and scale and
    /// eases on its own, so one can be moved, re-aimed or removed. Returns the later half, or nil when
    /// `time` is not inside the zoom or would leave a half shorter than a zoom can be.
    @discardableResult
    mutating func splitZoom(_ id: UUID, at time: Double) -> UUID? {
        guard let index = zooms.firstIndex(where: { $0.id == id }) else { return nil }
        let zoom = zooms[index]
        guard time - zoom.start >= ZoomSegment.minimumLength, zoom.end - time >= ZoomSegment.minimumLength else { return nil }
        let later = ZoomSegment(start: time, end: zoom.end, x: zoom.x, y: zoom.y, scale: zoom.scale)
        zooms[index].end = time
        zooms.insert(later, at: index + 1)
        return later.id
    }

    /// Replaces every zoom with ones made from the recording's clicks.
    mutating func generateZooms(from clicks: [ClickEvent], scale: Double = 1.8) {
        zooms = ZoomGenerator.segments(clicks: clicks, cuts: cuts, scale: scale)
    }
}
