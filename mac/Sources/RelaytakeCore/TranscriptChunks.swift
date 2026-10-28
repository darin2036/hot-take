import Foundation

/// The on-device model reads a few thousand words at a time, so a long recording is read in pieces and the
/// results merged. This only decides where the pieces break; the model calls are in the app target.
public enum TranscriptChunks {
    /// The most partial results merged in one step before the merge itself is merged again.
    public static let maxParts = 8

    /// Splits plain text into pieces of at most `maxCharacters`, breaking at line ends, then spaces, and only
    /// inside a word when a single word is longer than a piece (text with no spaces, such as Chinese).
    public static func split(_ text: String, maxCharacters: Int = SummaryPrompt.maxCharacters) -> [String] {
        let limit = max(1, maxCharacters)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed.isEmpty ? [] : [trimmed] }
        var pieces: [String] = []
        var current = ""
        func flush() {
            let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
            current = ""
        }
        for token in tokens(trimmed) {
            if token.count > limit {
                flush()
                var rest = Substring(token)
                while !rest.isEmpty {
                    pieces.append(String(rest.prefix(limit)))
                    rest = rest.dropFirst(limit)
                }
            } else {
                if current.count + token.count > limit { flush() }
                current += token
            }
        }
        flush()
        return pieces
    }

    /// Whitespace-separated words, each keeping the whitespace after it so pieces rejoin exactly.
    private static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var word = ""
        var inSpace = false
        for character in text {
            if character.isWhitespace {
                inSpace = true
            } else if inSpace {
                result.append(word)
                word = ""
                inSpace = false
            }
            word.append(character)
        }
        if !word.isEmpty { result.append(word) }
        return result
    }

    /// Runs of consecutive segments whose numbered lines (see `EditPrompt.numbered`) each fit `maxCharacters`.
    /// Every segment is in exactly one run, so nothing is skipped.
    public static func runs(of segments: [CaptionSegment], maxCharacters: Int = SummaryPrompt.maxCharacters) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start = 0
        while start < segments.count {
            let included = max(1, EditPrompt.numbered(Array(segments[start...]), maxCharacters: maxCharacters).included)
            runs.append(start..<(start + included))
            start += included
        }
        return runs
    }
}

extension SummaryPrompt {
    /// Asks for a short summary of one piece of a long transcript.
    public static func partPrompt(_ piece: String, number: Int, of count: Int) -> String {
        "Part \(number) of \(count) of the transcript of a long screen recording:\n\n\(piece)"
    }

    /// The condensed stand-in for a long transcript: one line per part, in order. It is read like a transcript,
    /// so the title, tags and the rest are written from it by the same prompts.
    public static func digest(of parts: [String]) -> String {
        "(This recording is long. Each line summarizes the next part of it.)\n"
            + parts.enumerated().map { "Part \($0.offset + 1): \($0.element)" }.joined(separator: "\n")
    }
}

extension AgentPrompt {
    /// The requests read from each part of a long recording, laid out so one more pass can merge them.
    public static func mergeText(_ requests: [AgentBrief.Request]) -> String {
        requests.enumerated().map { index, request in
            "Part \(index + 1) of the recording. Goal: \(request.goal)\nSteps:\n"
                + request.steps.map { "- \($0)" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    /// Joins requests without asking the model: the first goal, then every step in order (up to the limit).
    public static func combined(_ requests: [AgentBrief.Request]) -> AgentBrief.Request? {
        guard let goal = requests.map(\.goal).first(where: { !$0.isEmpty }) ?? requests.first?.goal else { return nil }
        return AgentBrief.Request(goal: goal, steps: Array(requests.flatMap(\.steps).prefix(maxSteps)))
    }
}

extension MetadataPrompt {
    /// Action items from each part of a long recording as one list, without repeats.
    public static func mergeNotes(_ parts: [String], limit: Int = 30) -> String {
        var seen = Set<String>()
        var lines: [String] = []
        for line in parts.flatMap({ $0.split(separator: "\n") }).map(String.init) {
            let key = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "-•* \t."))
            if key.isEmpty || !seen.insert(key).inserted { continue }
            lines.append(line)
            if lines.count == limit { break }
        }
        return lines.joined(separator: "\n")
    }
}
