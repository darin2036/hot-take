import Foundation

/// How captions look when they are drawn into the picture.
public enum CaptionStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic, bold, minimal, highlight
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .classic: "Classic"
        case .bold: "Bold"
        case .minimal: "Minimal"
        case .highlight: "Highlight"
        }
    }

    public var detail: String {
        switch self {
        case .classic: "White text on a dark box. Reads on any picture."
        case .bold: "Large heavy letters with a shadow and no box."
        case .minimal: "Small, quiet text with a soft shadow."
        case .highlight: "Dark text on a yellow box, like a highlighter."
        }
    }

    /// A line in this style, for showing what the style looks like.
    public var sampleOverlay: TextOverlay { overlay(text: "Aa", start: 0, end: 1, y: 0.5, id: UUID()) }

    /// A caption line in this style. Position is the vertical center as a fraction of the height.
    func overlay(text: String, start: Double, end: Double, y: Double, id: UUID) -> TextOverlay {
        var overlay = TextOverlay(id: id, text: text, start: start, end: end, y: y)
        switch self {
        case .classic:
            overlay.heightFraction = 0.05
        case .bold:
            overlay.fontFamily = "Impact"
            overlay.heightFraction = 0.075
            overlay.showsBackground = false
        case .minimal:
            overlay.isBold = false
            overlay.heightFraction = 0.042
            overlay.showsBackground = false
        case .highlight:
            overlay.heightFraction = 0.05
            overlay.color = .black
            overlay.boxColor = TextColor(red: 1, green: 0.84, blue: 0.1)
        }
        overlay.fades = false
        return overlay
    }
}

public enum CaptionPosition: String, Codable, CaseIterable, Identifiable, Sendable {
    case bottom, middle, top
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    var y: Double { self == .bottom ? 0.88 : self == .middle ? 0.5 : 0.12 }
}

/// Captions switched on for a Studio project. `cues` are transcript segments in the *original's* time;
/// the Studio maps them through the cuts, so removing a section removes its captions too.
public struct StudioCaptions: Codable, Equatable, Sendable {
    public var style: CaptionStyle
    public var position: CaptionPosition
    public var cues: [CaptionSegment]
    /// The language the cues are in when they are a translation of the transcript ("es", "ja"). Nil is what was said.
    public var language: String?

    public init(
        style: CaptionStyle = .classic, position: CaptionPosition = .bottom, cues: [CaptionSegment], language: String? = nil
    ) {
        self.style = style
        self.position = position
        self.cues = cues
        self.language = language
    }
}

public extension StudioProject {
    /// The caption lines as timed text on the *edited* timeline. Long segments are split into short lines,
    /// a line that was cut out disappears, and a line a cut runs through shows for the part that is kept.
    func captionOverlays(maxCharacters: Int = 42) -> [TextOverlay] {
        guard let captions else { return [] }
        var result: [TextOverlay] = []
        for cue in Captions.cues(from: captions.cues, maxCharacters: maxCharacters) {
            for span in cuts.outputSpans(forSource: TimeSpan(start: cue.start, end: cue.end)) where span.length >= 0.1 {
                // Stable ids, so the preview does not rebuild every line each time something changes.
                let n = result.count
                let id = UUID(uuid: (UInt8(truncatingIfNeeded: n), UInt8(truncatingIfNeeded: n >> 8), 0xCA, 0x9F, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
                result.append(captions.style.overlay(
                    text: cue.text, start: span.start, end: span.end, y: captions.position.y, id: id))
            }
        }
        return result
    }
}
