import Foundation

/// One word as the recognizer heard it ("um," with its punctuation), with the time it covers in the original.
public struct TimedWord: Codable, Equatable, Sendable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Finds filler sounds in the recognizer's timed words. Only sounds that are never a real word are looked for, so
/// "like", "so" and "you know" are left alone. The same words always give the same answer.
public enum FillerWords {
    /// English hesitation sounds. SpeechTranscriber writes some "uh"s as "ah", so that counts too.
    public static let sounds: Set<String> = ["um", "umm", "uhm", "uh", "uhh", "er", "erm", "ah", "ahh", "hmm", "hm", "mm"]

    /// "Um," → "um": lowercased, with punctuation removed.
    static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter })
    }

    public static func isFiller(_ text: String) -> Bool { sounds.contains(normalized(text)) }

    /// Each filler sound, or run of them ("um, uh"), as a proposed cut. The recognizer's word times usually include the
    /// pause around a filler, so cutting all of it closes the gap; `margin` is left at each end so the cut does not
    /// clip the words beside it.
    public static func find(in words: [TimedWord], margin: TimeInterval = 0.02, minLength: TimeInterval = 0.08) -> [EditSuggestion] {
        let ordered = words.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var found: [EditSuggestion] = []
        var index = 0
        while index < ordered.count {
            guard isFiller(ordered[index].text) else { index += 1; continue }
            var last = index
            while last + 1 < ordered.count, isFiller(ordered[last + 1].text) { last += 1 }
            // Never reach into the word before or after.
            let floor = index > 0 ? ordered[index - 1].end : 0
            let ceiling = last + 1 < ordered.count ? ordered[last + 1].start : ordered[last].end
            let span = TimeSpan(
                start: max(floor, ordered[index].start) + margin,
                end: min(ceiling, ordered[last].end) - margin)
            if span.length >= minLength {
                let said = ordered[index...last].map { normalized($0.text) }.joined(separator: ", ")
                found.append(EditSuggestion(kind: .filler, span: span, reason: "Filler: \u{201C}\(said)\u{201D}"))
            }
            index = last + 1
        }
        return found
    }
}

/// Editing a recording by its transcript: how much of each line is still in the edit, and which stretches of the
/// original a choice of lines covers.
public enum TranscriptCuts {
    public enum LineState: Equatable, Sendable {
        case kept
        /// Some of the line was cut, some is still there.
        case partlyCut
        case cut
    }

    public static func state(of line: CaptionSegment, in cuts: EditModel) -> LineState {
        let length = line.end - line.start
        guard length > 0 else { return cuts.outputTime(forSource: line.start) == nil ? .cut : .kept }
        let kept = cuts.outputSpans(forSource: TimeSpan(start: line.start, end: line.end)).reduce(0) { $0 + $1.length }
        if kept < min(0.05, length / 2) { return .cut }
        if kept > length - min(0.05, length / 2) { return .kept }
        return .partlyCut
    }

    /// The stretches of the original the chosen lines cover, with neighbouring lines joined into one.
    public static func spans(of lines: [CaptionSegment]) -> [TimeSpan] {
        EditSuggestions.merge(
            lines.filter { $0.end > $0.start }.map { TimeSpan(start: $0.start, end: $0.end) }.sorted { $0.start < $1.start })
    }

    /// The line playing at `source` seconds of the original, if any.
    public static func line(at source: TimeInterval, in lines: [CaptionSegment]) -> Int? {
        lines.lastIndex { $0.start <= source + 0.02 && source < $0.end }
    }
}
