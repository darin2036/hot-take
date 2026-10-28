import Foundation

public enum CaptionTranslationError: LocalizedError, Equatable {
    /// The translator returned nothing for a line that has words.
    case missing(line: Int)

    public var errorDescription: String? {
        switch self {
        case .missing(let line): "The translation left out line \(line + 1). Nothing was saved."
        }
    }
}

/// Putting translated text back into the transcript's lines. The system translator does the translating; this keeps
/// the timing, which always comes from the transcript and never from the translator.
public enum CaptionTranslation {
    /// The lines worth sending to a translator, as (line number, text). Blank lines are left out.
    public static func requests(for segments: [CaptionSegment]) -> [(line: Int, text: String)] {
        segments.enumerated().compactMap { index, segment in
            let text = clean(segment.text)
            return text.isEmpty ? nil : (index, text)
        }
    }

    /// The transcript's lines with their text replaced by `translated` (line number → text) and their timing kept.
    /// Throws if a line that has words came back empty, so a half-translated caption file is never saved.
    public static func merge(_ segments: [CaptionSegment], translated: [Int: String]) throws -> [CaptionSegment] {
        var result: [CaptionSegment] = []
        for (index, segment) in segments.enumerated() {
            guard !clean(segment.text).isEmpty else { continue }
            let text = clean(translated[index] ?? "")
            guard !text.isEmpty else { throw CaptionTranslationError.missing(line: index) }
            result.append(CaptionSegment(start: segment.start, end: segment.end, text: text))
        }
        return result
    }

    /// Line breaks and runs of spaces become single spaces, as in a corrected transcript line.
    static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// A file name for a translated caption file: "Name.es.vtt".
    public static func captionFileName(baseName: String, language: String) -> String {
        let safe = language.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }
        return "\(baseName).\(String(safe)).vtt"
    }
}
