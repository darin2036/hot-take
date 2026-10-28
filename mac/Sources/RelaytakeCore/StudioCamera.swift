import CoreGraphics
import Foundation

// A take recorded with a camera keeps its original screen video and the camera video apart, in a hidden
// folder beside the take. The take's own video already has the camera baked in at its default place;
// the Studio goes back to the originals so the camera bubble can be moved, resized or hidden, and
// Save Copy draws the result. These are the pure rules for that: the style, where the bubble sits,
// and which stretch of the camera video goes with which stretch of the screen video.

public enum CameraShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case circle, rounded
    public var id: String { rawValue }
    public var title: String { self == .circle ? "Circle" : "Rounded" }
}

public enum CameraCorner: String, Codable, CaseIterable, Identifiable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}

/// Where the presenter was placed while recording: the centre as fractions of the picture, and the diameter as a
/// fraction of its height.
public struct CameraPlacement: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var size: Double

    public init(x: Double, y: Double, size: Double) {
        self.x = x
        self.y = y
        self.size = size
    }
}

/// Where the camera video is and how it lines up with the screen video.
public struct CameraSource: Equatable, Sendable {
    public var url: URL
    /// Seconds after the screen recording began that the camera recording began (negative if it began first).
    public var offset: Double
    /// Where the bubble started out, if it was moved while recording. Nil means the default corner.
    public var placement: CameraPlacement?

    public init(url: URL, offset: Double, placement: CameraPlacement? = nil) {
        self.url = url
        self.offset = offset
        self.placement = placement
    }
}

/// How the camera looks in the picture. It sits in a corner (the default) or wherever it was dragged to.
public struct CameraBubble: Codable, Equatable, Sendable {
    public static let sizeRange = 0.1...0.5
    public static let nudgeRange = -1.0...1.0
    /// Space between the bubble and the picture's edge, as a fraction of the picture's height.
    public static let margin = 0.035

    public var isVisible = true
    public var shape: CameraShape = .circle
    /// The corner it is tucked into, or nil when it has been dragged somewhere else (then `x` and `y` apply).
    public var corner: CameraCorner? = .bottomLeft
    /// Centre as a fraction of the picture's width and height; used when `corner` is nil.
    public var x = 0.5
    public var y = 0.5
    /// Diameter as a fraction of the picture's height.
    public var size = 0.24
    /// Flip left to right, like a mirror. Off shows the camera the way others see you.
    public var isMirrored = false
    public var hasBorder = true
    /// Seconds added to the recorded offset, to line the camera up with the screen by hand.
    public var nudge = 0.0

    public init() {}

    public mutating func clamp() {
        size = min(Self.sizeRange.upperBound, max(Self.sizeRange.lowerBound, size))
        nudge = min(Self.nudgeRange.upperBound, max(Self.nudgeRange.lowerBound, nudge))
        x = min(1, max(0, x))
        y = min(1, max(0, y))
    }

    /// Puts the bubble where a drag ended, as fractions of the picture.
    public mutating func move(toX x: Double, y: Double) {
        corner = nil
        self.x = x
        self.y = y
        clamp()
    }

    /// The square the bubble occupies in a picture of `canvas` pixels (from the top-left), kept inside it.
    public func frame(in canvas: CGSize) -> CGRect {
        guard canvas.width > 0, canvas.height > 0 else { return .zero }
        let diameter = min(size * canvas.height, min(canvas.width, canvas.height))
        let inset = Self.margin * canvas.height
        let origin: CGPoint
        if let corner {
            let left = corner == .topLeft || corner == .bottomLeft
            let top = corner == .topLeft || corner == .topRight
            origin = CGPoint(x: left ? inset : canvas.width - inset - diameter, y: top ? inset : canvas.height - inset - diameter)
        } else {
            origin = CGPoint(x: x * canvas.width - diameter / 2, y: y * canvas.height - diameter / 2)
        }
        return CGRect(
            x: min(max(0, origin.x), max(0, canvas.width - diameter)),
            y: min(max(0, origin.y), max(0, canvas.height - diameter)), width: diameter, height: diameter)
    }
}

public enum CameraTimeline {
    /// One stretch of the camera video that plays during a kept stretch of the screen video.
    public struct Piece: Equatable, Sendable {
        /// Where in the camera video it starts, and how long it runs.
        public var cameraStart: Double
        public var length: Double
        /// Where it starts within the kept stretch of the screen video (after the camera had begun).
        public var delay: Double
    }

    /// For each kept stretch of the screen video (in the original's time), the part of the camera video
    /// that goes with it. The camera may have started later (or earlier) than the screen, and is shorter
    /// or longer than it; wherever it has no footage the piece is shorter or missing, and the bubble
    /// is simply not shown there.
    public static func pieces(
        for segments: [TimeSpan], offset: Double, nudge: Double = 0, cameraDuration: Double
    ) -> [Piece?] {
        let shift = offset + nudge
        return segments.map { segment in
            let start = segment.start - shift
            let end = segment.end - shift
            let clippedStart = max(start, 0)
            let clippedEnd = min(end, cameraDuration)
            guard clippedEnd - clippedStart > 0.01 else { return nil }
            return Piece(cameraStart: clippedStart, length: clippedEnd - clippedStart, delay: clippedStart - start)
        }
    }
}
