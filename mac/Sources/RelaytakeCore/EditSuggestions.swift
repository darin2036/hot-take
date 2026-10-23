import Foundation

/// A proposed cut. Nothing is applied until the user clicks it.
public struct EditSuggestion: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// Found by measuring audio levels (or gaps in the transcript). Exact, not a guess.
        case silence
        /// A sentence said again straight afterwards, or started and restarted. Found by comparing the words of
        /// neighbouring transcript lines, so it is predictable, but the transcript may be wrong, so it is a proposal.
        case restart
        /// Recommended by the on-device language model from the transcript. A suggestion only.
        case recommended
    }

    public let kind: Kind
    public let span: TimeSpan
    public let reason: String

    public var id: String { "\(kind.rawValue)-\(Int((span.start * 100).rounded()))-\(Int((span.end * 100).rounded()))" }

    public init(kind: Kind, span: TimeSpan, reason: String) {
        self.kind = kind
        self.span = span
        self.reason = reason
    }
}

/// Finds quiet stretches from a series of loudness readings. Pure arithmetic: a language model
/// cannot hear audio, so this is measured instead.
public enum SilenceDetector {
    /// A threshold relative to this recording's own noise floor: a little above its quietest
    /// moments, kept within a sensible range so a very quiet room is not treated as all silence.
    public static func threshold(levels: [Double]) -> Double {
        let finite = levels.filter { $0.isFinite }.sorted()
        guard !finite.isEmpty else { return -45 }
        // The 10th percentile: the level that the quietest tenth of the recording stays below.
        let floor = finite[Int(Double(finite.count - 1) * 0.1)]
        return min(-35, max(-60, floor + 8))
    }

    /// Runs of windows quieter than `thresholdDB` that last at least `minDuration` seconds.
    /// `levels[i]` covers `i * windowSeconds ..< (i + 1) * windowSeconds`.
    public static func quietSpans(
        levels: [Double], windowSeconds: Double, thresholdDB: Double, minDuration: Double
    ) -> [TimeSpan] {
        guard windowSeconds > 0 else { return [] }
        var spans: [TimeSpan] = []
        var runStart: Int?
        func close(at end: Int) {
            guard let start = runStart else { return }
            let span = TimeSpan(start: Double(start) * windowSeconds, end: Double(end) * windowSeconds)
            if span.length >= minDuration { spans.append(span) }
            runStart = nil
        }
        for (index, level) in levels.enumerated() {
            if level < thresholdDB {
                if runStart == nil { runStart = index }
            } else {
                close(at: index)
            }
        }
        close(at: levels.count)
        return spans
    }

    /// Shrinks each span by `pad` seconds at both ends so a cut leaves a natural breath of silence,
    /// dropping any that become shorter than `minLength`.
    public static func trimmed(_ spans: [TimeSpan], by pad: Double, minLength: Double) -> [TimeSpan] {
        spans.compactMap { span in
            let trimmed = TimeSpan(start: span.start + pad, end: span.end - pad)
            return trimmed.length >= minLength ? trimmed : nil
        }
    }
}

/// Long pauses between spoken segments, from the transcript's own timing.
public enum TranscriptGaps {
    public static func gaps(segments: [CaptionSegment], duration: Double, minGap: Double) -> [TimeSpan] {
        let ordered = segments.sorted { $0.start < $1.start }
        var spans: [TimeSpan] = []
        var cursor = 0.0
        for segment in ordered {
            if segment.start - cursor >= minGap { spans.append(TimeSpan(start: cursor, end: segment.start)) }
            cursor = max(cursor, segment.end)
        }
        if duration - cursor >= minGap { spans.append(TimeSpan(start: cursor, end: duration)) }
        return spans
    }
}

/// Finds places where the speaker said something, then said it again: the first attempt is the candidate cut.
/// This compares words only, so the same transcript always gives the same answer.
public enum RestartFinder {
    /// Lowercased words with punctuation removed.
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map(String.init)
    }

    /// Whether `first` is an earlier attempt at what `second` says: its words open `second`, or most of its words
    /// come again in `second`.
    static func isRestart(_ first: [String], _ second: [String]) -> Bool {
        guard first.count >= 3, second.count >= first.count - 1 else { return false }
        // Started and abandoned, then said whole: "so what I want to" / "so what I want to show you is".
        let overlap = min(first.count, second.count)
        if first.count >= 3, Array(second.prefix(overlap)) == Array(first.prefix(overlap)), second.count > first.count - 1 {
            return true
        }
        // The same sentence again, perhaps with a word changed.
        guard first.count >= 4 else { return false }
        let remaining = Dictionary(second.map { ($0, 1) }, uniquingKeysWith: +)
        var left = remaining
        var shared = 0
        for word in first where (left[word] ?? 0) > 0 {
            left[word]! -= 1
            shared += 1
        }
        return Double(shared) / Double(first.count) >= 0.75
    }

    /// Each segment that the next one repeats or completes. `maxGap` is the longest pause allowed between the two
    /// for them to count as one attempt and its retry.
    public static func find(in segments: [CaptionSegment], maxGap: Double = 6) -> [EditSuggestion] {
        let ordered = segments.sorted { $0.start < $1.start }
        var found: [EditSuggestion] = []
        for index in ordered.indices.dropLast() {
            let first = ordered[index], second = ordered[index + 1]
            guard second.start - first.end <= maxGap, first.end > first.start else { continue }
            if isRestart(words(first.text), words(second.text)) {
                let said = first.text.trimmingCharacters(in: .whitespacesAndNewlines)
                found.append(EditSuggestion(
                    kind: .restart, span: TimeSpan(start: first.start, end: first.end),
                    reason: "Said again just after: \"\(said.count > 60 ? String(said.prefix(57)) + "…" : said)\""))
            }
        }
        return found
    }
}

/// Asks the language model which parts of a transcript could be cut, by segment number.
/// The model never invents timestamps: it names segments, and times come from the transcript.
public enum EditPrompt {
    public static let instructions = """
        You review the transcript of a screen recording and flag only restarts that a speaker would want \
        cut. Most recordings need no cuts, and NONE is the correct answer for a clean recording.
        A cut is allowed only for: a sentence that is said again immediately afterwards (cut the first \
        attempt), or a sentence abandoned halfway and then started again. A greeting, a conclusion, an \
        explanation, a demonstration, filler words, or a sentence that is merely casual is NEVER a cut. \
        Suggest at most three cuts.
        Reply with one line per cut in exactly this format, using the bracketed segment numbers:
        CUT <first>-<last>: <short reason that names the repeated or filler words>
        If nothing qualifies, reply exactly: NONE
        """

    /// Numbered transcript lines, keeping as many leading segments as fit the model's budget.
    /// Returns the text and how many segments it includes.
    public static func numbered(_ segments: [CaptionSegment], maxCharacters: Int = SummaryPrompt.maxCharacters)
        -> (text: String, included: Int)
    {
        var text = ""
        var included = 0
        for (index, segment) in segments.enumerated() {
            let line = "[\(index + 1)] \(segment.text)\n"
            if text.count + line.count > maxCharacters { break }
            text += line
            included += 1
        }
        return (text, included)
    }

    public static func prompt(for segments: [CaptionSegment]) -> (text: String, included: Int) {
        let numbered = numbered(segments)
        return ("Transcript, one numbered segment per line:\n\n" + numbered.text, numbered.included)
    }

    /// Parses `CUT 4-5: reason` lines. Anything out of range, reversed or malformed is dropped.
    public static func parse(_ reply: String, segments: [CaptionSegment], limit: Int = 5) -> [EditSuggestion] {
        var suggestions: [EditSuggestion] = []
        for raw in reply.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "-•* \t"))
            guard line.uppercased().hasPrefix("CUT") else { continue }
            let rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            guard let colon = rest.firstIndex(of: ":") else { continue }
            let range = rest[..<colon].replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            let reason = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = range.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = parts.first.flatMap({ Int($0) }), let last = parts.count > 1 ? Int(parts[1]) : first,
                  first >= 1, last >= first, last <= segments.count
            else { continue }
            let span = TimeSpan(start: segments[first - 1].start, end: segments[last - 1].end)
            guard span.length > 0 else { continue }
            suggestions.append(EditSuggestion(kind: .recommended, span: span, reason: reason.isEmpty ? "Suggested cut" : reason))
            if suggestions.count == limit { break }
        }
        return suggestions
    }
}

public enum EditSuggestions {
    /// Combines measured silence (audio levels and transcript pauses) with the model's recommendations:
    /// overlapping silences are merged, a silence inside a recommended cut is dropped as redundant,
    /// and the result is in time order.
    public static func combine(
        audioSilences: [TimeSpan], transcriptGaps: [TimeSpan], restarts: [EditSuggestion] = [], recommended: [EditSuggestion]
    ) -> [EditSuggestion] {
        // A model suggestion that overlaps a restart the word comparison already found says the same thing twice.
        let model = recommended.filter { candidate in
            !restarts.contains { $0.span.start < candidate.span.end && candidate.span.start < $0.span.end }
        }
        let proposals = restarts + model
        let silences = merge((audioSilences + transcriptGaps).sorted { $0.start < $1.start })
            .filter { silence in
                !proposals.contains { $0.span.start <= silence.start && $0.span.end >= silence.end }
            }
            .map { span in
                EditSuggestion(kind: .silence, span: span, reason: "Quiet for \(String(format: "%.1f", span.length)) s")
            }
        return (silences + proposals).sorted { $0.span.start < $1.span.start }
    }

    /// Merges touching or overlapping spans (input must be sorted by start).
    static func merge(_ spans: [TimeSpan]) -> [TimeSpan] {
        var result: [TimeSpan] = []
        for span in spans {
            if var last = result.last, span.start <= last.end {
                last.end = max(last.end, span.end)
                result[result.count - 1] = last
            } else {
                result.append(span)
            }
        }
        return result
    }
}
