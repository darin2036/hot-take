import CoreGraphics
import Foundation

// Helpers that make it quicker and safer for an agent to record a demo: knowing where each display is so it can aim real
// clicks at it, folding a retake into the beat it replaces, keeping automatic zooms from piling up, choosing the pictures
// that let an agent check a finished video, and tidying what a privacy check found. All pure logic; nothing here touches
// the screen or the network.

// MARK: Displays

/// One display, in the same numbering `hottake start --display N` uses. The rectangle is in points with the origin at the top-left
/// of the main display (the space the mouse is moved in), so an agent can aim a click at it directly.
public struct AgentDisplay: Codable, Equatable, Sendable {
    public var number: Int
    public var name: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// Pixels per point (2 on a Retina display).
    public var scale: Double
    public var isMain: Bool

    enum CodingKeys: String, CodingKey { case number, name, x, y, width, height, scale, isMain = "main" }

    public init(number: Int, name: String, x: Double, y: Double, width: Double, height: Double, scale: Double, isMain: Bool) {
        self.number = number; self.name = name; self.x = x; self.y = y; self.width = width; self.height = height
        self.scale = scale; self.isMain = isMain
    }

    /// A point given from this display's own top-left corner, as a point on the whole desktop. Nil if it is off the display.
    public func desktopPoint(x px: Double, y py: Double) -> (x: Double, y: Double)? {
        guard px.isFinite, py.isFinite, px >= 0, py >= 0, px < width, py < height else { return nil }
        return (x + px, y + py)
    }
}

public enum AgentDisplays {
    /// A screen as the system reports it: a frame with the origin at the bottom-left of the main display.
    public struct Screen: Equatable, Sendable {
        public var name: String
        public var frame: CGRect
        public var scale: Double
        public init(name: String, frame: CGRect, scale: Double) { self.name = name; self.frame = frame; self.scale = scale }
    }

    /// The displays numbered from 1 in the order given, with `screens[0]` taken as the main one (it holds the menu bar),
    /// turned from the system's bottom-left origin to the top-left one the mouse uses.
    public static func list(_ screens: [Screen]) -> [AgentDisplay] {
        guard let main = screens.first else { return [] }
        return screens.enumerated().map { index, screen in
            AgentDisplay(
                number: index + 1, name: screen.name,
                x: Double(screen.frame.minX), y: Double(main.frame.maxY - screen.frame.maxY),
                width: Double(screen.frame.width), height: Double(screen.frame.height),
                scale: screen.scale, isMain: index == 0)
        }
    }
}

// MARK: Retakes

/// A step that went wrong is redone, not stopped for: the agent marks `Retake: Name`, does the step again, and the edit cuts the
/// failed attempt for it. The retake then stands for the beat itself, so its narration, chapter and zooms keep the beat's name.
public enum AgentRetakes {
    public static let prefix = "Retake:"

    /// The beat a marker redoes ("Retake: Open Studio" is a redo of "Open Studio"), or nil if it is not a retake.
    public static func beatName(of name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > prefix.count, trimmed.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        let rest = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    public struct Resolution: Equatable, Sendable {
        /// The markers with each failed attempt removed and each retake renamed to its beat.
        public var markers: [AgentMarker]
        /// The failed attempts: from the earlier marker of that name up to its retake.
        public var cuts: [TimeSpan]
        public var warnings: [String]
    }

    public static func resolve(_ markers: [AgentMarker]) -> Resolution {
        var kept: [AgentMarker] = []
        var cuts: [TimeSpan] = []
        var warnings: [String] = []
        for marker in markers.sorted(by: { $0.time < $1.time }) {
            guard let beat = beatName(of: marker.name) else {
                kept.append(marker)
                continue
            }
            if let index = kept.lastIndex(where: { $0.name.caseInsensitiveCompare(beat) == .orderedSame }) {
                if marker.time - kept[index].time >= EditModel.minimumSegment {
                    cuts.append(TimeSpan(start: kept[index].time, end: marker.time))
                }
                kept.remove(at: index)
            } else {
                warnings.append("“\(marker.name)” redoes a step, but no earlier marker is named “\(beat)”; nothing was cut for it.")
            }
            kept.append(AgentMarker(name: beat, time: marker.time))
        }
        return Resolution(markers: kept, cuts: cuts, warnings: warnings)
    }
}

// MARK: Zooms

public enum ZoomCap {
    /// The zooms with the busiest ones dropped so no more than about `maxPerMinute` remain: each zoom is kept only if it starts
    /// at least a gap after the one kept before it. Order is preserved. A limit of zero or less changes nothing.
    public static func thinned(_ zooms: [ZoomSegment], maxPerMinute: Double) -> [ZoomSegment] {
        guard maxPerMinute > 0 else { return zooms }
        let gap = 60 / maxPerMinute
        var result: [ZoomSegment] = []
        for zoom in zooms.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, zoom.start - last.start < gap { continue }
            result.append(zoom)
        }
        return result
    }
}

// MARK: Pictures for checking a finished video

public enum AgentFrames {
    public static let defaultCount = 12
    public static let maximum = 60

    /// The moments to look at. Times the agent asked for win; else the middle of each chapter (where its action usually is, not its
    /// first second); else evenly spread through the
    /// video. Always inside the video, in order, with no two nearly the same.
    public static func times(requested: [Double], chapterStarts: [Double], duration: Double, count: Int = defaultCount) -> [Double] {
        guard duration > 0 else { return [] }
        let last = max(0, duration - 0.05)
        var raw: [Double]
        if !requested.isEmpty {
            raw = requested
        } else if !chapterStarts.isEmpty {
            let starts = chapterStarts.sorted()
            raw = starts.enumerated().map { index, start in
                let next = index + 1 < starts.count ? starts[index + 1] : duration
                return start + max(0, (next - start) / 2)
            }
        } else {
            let n = max(1, count)
            raw = (0..<n).map { (Double($0) + 0.5) / Double(n) * duration }
        }
        var result: [Double] = []
        for time in raw.filter(\.isFinite).map({ min(last, max(0, $0)) }).sorted() {
            if let previous = result.last, time - previous < 0.1 { continue }
            result.append(time)
        }
        return Array(result.prefix(maximum))
    }

    /// "Frame 03 at 0m12s.png".
    public static func fileName(number: Int, of total: Int, time: Double) -> String {
        let digits = max(2, String(total).count)
        let whole = Int(time.rounded(.down))
        return "Frame \(String(format: "%0\(digits)d", number)) at \(whole / 60)m\(String(format: "%02d", whole % 60))s.png"
    }

    /// How many pictures sit side by side on the contact sheet.
    public static func columns(for count: Int) -> Int {
        switch count {
        case ..<5: 2
        case ..<10: 3
        default: 4
        }
    }
}

// MARK: What a privacy check found

public struct AgentFinding: Codable, Equatable, Sendable {
    /// What kind of thing it looks like ("Email address").
    public var kind: String
    /// The text with most of it hidden, so listing it does not show the secret again.
    public var preview: String
    /// Seconds into the picture or video it was seen at (0 for a single screenshot).
    public var time: Double
    /// Where it is, 0...1 from the top-left of the picture.
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(kind: String, preview: String, time: Double, x: Double, y: Double, width: Double, height: Double) {
        self.kind = kind; self.preview = preview; self.time = time
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public init(_ sighting: SensitiveSighting) {
        self.init(
            kind: sighting.kind.title, preview: SensitiveText.masked(sighting.text), time: sighting.time,
            x: Double(sighting.rect.minX), y: Double(sighting.rect.minY),
            width: Double(sighting.rect.width), height: Double(sighting.rect.height))
    }
}
