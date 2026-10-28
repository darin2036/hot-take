import CoreGraphics
import Foundation

// Marks drawn on the recorded picture in the Studio: arrows, boxes and blurred regions, and rings at
// the clicks that were noted while recording. They live on the edited timeline like text and zooms do, so
// a cut ripples through them. Positions are points in the *recorded* picture (0...1 from the top-left), so
// a mark stays on what it points at when a backdrop insets the window or a zoom magnifies it. All the
// rules here are pure and tested; the compositor only draws what they say.

public struct ShapeOverlay: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case arrow, box, blur

        public var title: String {
            switch self {
            case .arrow: "Arrow"
            case .box: "Box"
            case .blur: "Blur"
            }
        }

        public var symbol: String {
            switch self {
            case .arrow: "arrow.up.right"
            case .box: "rectangle"
            case .blur: "drop.halffull"
            }
        }
    }

    public static let minimumLength = 0.5
    /// Stroke width as a fraction of the picture's shorter side.
    public static let lineWidthRange = 0.003...0.02
    /// Blur radius as a fraction of the picture's shorter side.
    public static let blurRange = 0.004...0.04
    /// Smallest a box or blur can be, so it is never dragged down to nothing.
    public static let minimumSide = 0.02

    public let id: UUID
    public var kind: Kind
    /// Output-timeline seconds.
    public var start: Double
    public var end: Double
    /// An arrow runs from (x1, y1) to its head at (x2, y2). A box or blur fills the rectangle between the two
    /// corners, whichever way they were dragged.
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double
    public var color: TextColor
    public var lineWidth: Double
    public var blurRadius: Double

    public var length: Double { end - start }

    /// The rectangle between the two points, as fractions of the picture.
    public var rect: CGRect {
        CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
    }

    public init(
        id: UUID = UUID(), kind: Kind, start: Double, end: Double,
        x1: Double, y1: Double, x2: Double, y2: Double,
        color: TextColor = ShapeOverlay.standardColor, lineWidth: Double = 0.007, blurRadius: Double = 0.015
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
        self.color = color
        self.lineWidth = lineWidth
        self.blurRadius = blurRadius
    }

    public static let standardColor = TextColor(red: 1, green: 0.27, blue: 0.23)

    /// A new mark of `kind` in the middle of the picture, for the person to drag into place.
    public static func standard(_ kind: Kind, start: Double, end: Double) -> ShapeOverlay {
        switch kind {
        case .arrow: ShapeOverlay(kind: .arrow, start: start, end: end, x1: 0.32, y1: 0.62, x2: 0.5, y2: 0.45)
        case .box: ShapeOverlay(kind: .box, start: start, end: end, x1: 0.3, y1: 0.35, x2: 0.7, y2: 0.62)
        case .blur: ShapeOverlay(kind: .blur, start: start, end: end, x1: 0.3, y1: 0.4, x2: 0.7, y2: 0.55)
        }
    }

    /// How visible the mark is `time` seconds into the edited video: a short fade in and out around its
    /// stretch. A blur switches quickly so a name is never half-readable.
    public func opacity(at time: Double) -> Double {
        guard time >= start, time <= end else { return 0 }
        let fade = max(0.001, min(kind == .blur ? 0.06 : 0.15, length / 2))
        return min(1, (time - start) / fade, (end - time) / fade)
    }
}

/// Where the pieces of an arrow sit, in the same 0...1 picture coordinates as the arrow itself. The caller
/// draws the shaft up to `shaftEnd`, so a thick line does not poke out past the point of the head.
public struct ArrowGeometry: Equatable, Sendable {
    public var tail: CGPoint
    public var tip: CGPoint
    public var shaftEnd: CGPoint
    public var wingA: CGPoint
    public var wingB: CGPoint

    /// - Parameters:
    ///   - aspect: picture width divided by height, because the head must look the same on a wide picture.
    ///   - lineWidth: stroke width as a fraction of the picture's shorter side.
    public init(from tail: CGPoint, to tip: CGPoint, lineWidth: Double, aspect: Double) {
        self.tail = tail
        self.tip = tip
        // Work in a square space so angles are true, then bring the points back.
        let aspect = max(0.1, aspect)
        let dx = (tip.x - tail.x) * aspect
        let dy = tip.y - tail.y
        let length = max(1e-9, (dx * dx + dy * dy).squareRoot())
        let ux = dx / length, uy = dy / length
        let shorter = aspect >= 1 ? 1.0 : aspect  // the picture's shorter side, in this space (its height is 1)
        let unit = lineWidth * shorter
        let head = min(length * 0.6, max(unit * 5, 0.025))
        let half = head * 0.55
        let baseX = tip.x * aspect - ux * head, baseY = tip.y - uy * head
        func back(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x / aspect, y: y) }
        shaftEnd = back(baseX + ux * head * 0.35, baseY + uy * head * 0.35)
        wingA = back(baseX - uy * half, baseY + ux * half)
        wingB = back(baseX + uy * half, baseY - ux * half)
    }
}

/// Rings that pulse where the mouse was clicked while recording.
public struct ClickHighlight: Codable, Equatable, Sendable {
    /// Ring radius at its largest, as a fraction of the picture's shorter side.
    public static let sizeRange = 0.025...0.1
    /// Seconds each ring takes to open and fade.
    public static let duration = 0.6
    public static let standardColor = TextColor(red: 1, green: 0.84, blue: 0.1)

    public var color: TextColor
    public var size: Double
    /// The clicks noted while recording, in recording time. They are mapped through the cuts when drawn, so a
    /// click in a section that was cut out shows nothing.
    public var clicks: [ClickEvent]

    public init(clicks: [ClickEvent], color: TextColor = ClickHighlight.standardColor, size: Double = 0.05) {
        self.clicks = clicks
        self.color = color
        self.size = min(Self.sizeRange.upperBound, max(Self.sizeRange.lowerBound, size))
    }
}

public struct ClickRing: Equatable, Sendable {
    /// A point in the recorded picture, 0...1 from the top-left.
    public var x: Double
    public var y: Double
    /// 0...1 of the full ring radius.
    public var scale: Double
    public var opacity: Double
}

/// The clicks of one highlight laid on the edited timeline, ready to ask what is showing at a moment.
public struct ClickHighlightTimeline: Sendable {
    public struct Moment: Equatable, Sendable {
        public var time: Double
        public var x: Double
        public var y: Double
    }

    public let highlight: ClickHighlight
    /// Where each click that survived the cuts falls on the edited video, earliest first.
    public let moments: [Moment]

    public init(highlight: ClickHighlight, cuts: EditModel) {
        self.highlight = highlight
        moments = highlight.clicks.compactMap { click in
            cuts.outputTime(forSource: click.time).map { Moment(time: $0, x: click.x, y: click.y) }
        }.sorted { $0.time < $1.time }
    }

    /// The rings visible at `time`. Each opens from a small dot and fades as it grows.
    public func rings(at time: Double) -> [ClickRing] {
        var result: [ClickRing] = []
        for moment in moments {
            if moment.time > time { break }
            let progress = (time - moment.time) / ClickHighlight.duration
            guard progress >= 0, progress < 1 else { continue }
            let eased = ZoomCamera.ease(progress)
            result.append(ClickRing(
                x: moment.x, y: moment.y, scale: 0.35 + 0.65 * eased,
                opacity: min(1, (1 - progress) * 1.3)))
        }
        return result
    }
}

public extension CanvasLayout {
    /// A point in the recorded picture (0...1) as it appears on screen right now: inside the backdrop, and
    /// moved by the zoom that is showing. The result is 0...1 across what is on screen.
    static func shownPoint(forSource x: Double, _ y: Double, content: CGRect, canvas: CGSize, zoom: ZoomCamera.State) -> CGPoint {
        let point = canvasPoint(forSource: x, y, content: content, canvas: canvas)
        let focus = canvasPoint(forSource: zoom.focusX, zoom.focusY, content: content, canvas: canvas)
        let crop = ZoomCamera.crop(zoom: zoom.zoom, focusX: focus.x, focusY: focus.y)
        return CGPoint(x: (point.x - crop.minX) / crop.width, y: (point.y - crop.minY) / crop.height)
    }

    /// The reverse: a spot on screen (0...1) as a point in the recorded picture, kept inside it.
    static func sourcePoint(forShown x: Double, _ y: Double, content: CGRect, canvas: CGSize, zoom: ZoomCamera.State) -> CGPoint {
        let focus = canvasPoint(forSource: zoom.focusX, zoom.focusY, content: content, canvas: canvas)
        let crop = ZoomCamera.crop(zoom: zoom.zoom, focusX: focus.x, focusY: focus.y)
        return sourcePoint(forCanvas: crop.minX + x * crop.width, crop.minY + y * crop.height, content: content, canvas: canvas)
    }
}

public extension StudioProject {
    func shape(_ id: UUID) -> ShapeOverlay? { shapes.first { $0.id == id } }

    /// Adds a mark of `kind` at `time`, lasting a few seconds, in the middle of the picture.
    @discardableResult
    mutating func addShape(_ kind: ShapeOverlay.Kind, at time: Double) -> UUID {
        let total = outputDuration
        let start = min(max(0, time), max(0, total - ShapeOverlay.minimumLength))
        let shape = ShapeOverlay.standard(kind, start: start, end: min(total, start + 4))
        shapes.append(shape)
        return shape.id
    }

    mutating func updateShape(_ id: UUID, _ change: (inout ShapeOverlay) -> Void) {
        guard let index = shapes.firstIndex(where: { $0.id == id }) else { return }
        let total = outputDuration
        var shape = shapes[index]
        change(&shape)
        for keyPath in [\ShapeOverlay.x1, \.y1, \.x2, \.y2] { shape[keyPath: keyPath] = min(1, max(0, shape[keyPath: keyPath])) }
        if shape.kind != .arrow {
            // A box or blur is never squeezed to a line.
            if abs(shape.x2 - shape.x1) < ShapeOverlay.minimumSide { shape.x2 = shape.x1 + (shape.x2 >= shape.x1 ? 1 : -1) * ShapeOverlay.minimumSide }
            if abs(shape.y2 - shape.y1) < ShapeOverlay.minimumSide { shape.y2 = shape.y1 + (shape.y2 >= shape.y1 ? 1 : -1) * ShapeOverlay.minimumSide }
            for keyPath in [\ShapeOverlay.x1, \.y1, \.x2, \.y2] { shape[keyPath: keyPath] = min(1, max(0, shape[keyPath: keyPath])) }
        }
        shape.lineWidth = min(ShapeOverlay.lineWidthRange.upperBound, max(ShapeOverlay.lineWidthRange.lowerBound, shape.lineWidth))
        shape.blurRadius = min(ShapeOverlay.blurRange.upperBound, max(ShapeOverlay.blurRange.lowerBound, shape.blurRadius))
        shape.start = min(max(0, shape.start), max(0, total - ShapeOverlay.minimumLength))
        shape.end = min(total, max(shape.end, shape.start + ShapeOverlay.minimumLength))
        shapes[index] = shape
    }

    /// Moves a mark in time, keeping its length, within the video.
    mutating func moveShape(_ id: UUID, to start: Double) {
        let total = outputDuration
        updateShape(id) { shape in
            let length = shape.length
            shape.start = min(max(0, start), max(0, total - length))
            shape.end = shape.start + length
        }
    }

    /// Slides a mark across the picture by a fraction of the picture, staying inside it.
    mutating func nudgeShape(_ id: UUID, byX dx: Double, y dy: Double) {
        updateShape(id) { shape in
            let x1 = shape.x1, y1 = shape.y1, x2 = shape.x2, y2 = shape.y2
            // Stop at the edge as a whole, so the mark keeps its size instead of squashing against it.
            let ddx = min(max(dx, -min(x1, x2)), 1 - max(x1, x2))
            let ddy = min(max(dy, -min(y1, y2)), 1 - max(y1, y2))
            shape.x1 = x1 + ddx; shape.x2 = x2 + ddx
            shape.y1 = y1 + ddy; shape.y2 = y2 + ddy
        }
    }

    mutating func removeShape(_ id: UUID) { shapes.removeAll { $0.id == id } }

    /// Splits a mark in two at `time`; both halves look the same. Returns the later half, or nil when `time`
    /// is not inside the mark or would leave a half shorter than a mark can be.
    @discardableResult
    mutating func splitShape(_ id: UUID, at time: Double) -> UUID? {
        guard let index = shapes.firstIndex(where: { $0.id == id }) else { return nil }
        let shape = shapes[index]
        guard time - shape.start >= ShapeOverlay.minimumLength, shape.end - time >= ShapeOverlay.minimumLength else { return nil }
        var later = shape
        later = ShapeOverlay(
            kind: shape.kind, start: time, end: shape.end, x1: shape.x1, y1: shape.y1, x2: shape.x2, y2: shape.y2,
            color: shape.color, lineWidth: shape.lineWidth, blurRadius: shape.blurRadius)
        shapes[index].end = time
        shapes.insert(later, at: index + 1)
        return later.id
    }

    /// Which lane (0, 1, …) each mark sits in so marks that overlap in time do not hide each other on the timeline.
    func shapeLanes() -> [UUID: Int] {
        var laneEnds: [Double] = []
        var result: [UUID: Int] = [:]
        for shape in shapes.sorted(by: { $0.start < $1.start }) {
            if let lane = laneEnds.firstIndex(where: { $0 <= shape.start + 0.001 }) {
                laneEnds[lane] = shape.end
                result[shape.id] = lane
            } else {
                laneEnds.append(shape.end)
                result[shape.id] = laneEnds.count - 1
            }
        }
        return result
    }

    /// Turns click rings on (using the clicks noted while recording) or off.
    mutating func setClickHighlights(on: Bool, clicks: [ClickEvent]) {
        guard on else { clickHighlight = nil; return }
        if clickHighlight == nil { clickHighlight = ClickHighlight(clicks: clicks) }
    }
}
