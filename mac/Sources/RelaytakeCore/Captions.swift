import Foundation

/// One timed piece of transcript text.
public struct CaptionSegment: Equatable, Sendable, Codable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Turning hand-edited text back into transcript lines.
public enum TranscriptEditing {
    /// Puts edited text into the lines it came from, keeping each line's timing. Line breaks become spaces (a blank line
    /// would end a caption early), extra spaces are trimmed, and a line left empty is dropped.
    public static func apply(_ edits: [String], to segments: [CaptionSegment]) -> [CaptionSegment] {
        var result: [CaptionSegment] = []
        for (index, segment) in segments.enumerated() {
            let text = (index < edits.count ? edits[index] : segment.text)
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !text.isEmpty else { continue }
            result.append(CaptionSegment(start: segment.start, end: segment.end, text: text))
        }
        return result
    }
}

public enum Captions {
    /// Splits long segments into readable cues, dividing time in proportion to text length.
    public static func cues(from segments: [CaptionSegment], maxCharacters: Int = 80) -> [CaptionSegment] {
        var cues: [CaptionSegment] = []
        for segment in segments {
            let words = segment.text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !words.isEmpty else { continue }

            // Even out line lengths so a long sentence doesn't end in a two-word orphan.
            let characters = words.reduce(0) { $0 + $1.count + 1 } - 1
            let lineCount = max(1, (characters + maxCharacters - 1) / maxCharacters)
            let target = min(maxCharacters, (characters + lineCount - 1) / lineCount + 3)

            var lines: [String] = []
            var current = ""
            for word in words {
                if !current.isEmpty && current.count + 1 + word.count > target {
                    lines.append(current)
                    current = word
                } else {
                    current = current.isEmpty ? word : current + " " + word
                }
            }
            if !current.isEmpty { lines.append(current) }

            let total = Double(lines.reduce(0) { $0 + $1.count })
            let duration = max(0, segment.end - segment.start)
            var cursor = segment.start
            for line in lines {
                let share = total > 0 ? duration * Double(line.count) / total : 0
                cues.append(CaptionSegment(start: cursor, end: cursor + share, text: line))
                cursor += share
            }
        }
        return cues
    }

    public static func timestamp(_ seconds: TimeInterval, millisecondSeparator: Character) -> String {
        let totalMilliseconds = Int((max(0, seconds) * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = totalMilliseconds / 60_000 % 60
        let secs = totalMilliseconds / 1000 % 60
        let millis = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, secs, String(millisecondSeparator), millis)
    }

    public static func webVTT(_ segments: [CaptionSegment]) -> String {
        var output = "WEBVTT\n\n"
        for cue in cues(from: segments) {
            output += "\(timestamp(cue.start, millisecondSeparator: "."))"
            output += " --> \(timestamp(cue.end, millisecondSeparator: "."))\n\(cue.text)\n\n"
        }
        return output
    }

    public static func srt(_ segments: [CaptionSegment]) -> String {
        var output = ""
        for (index, cue) in cues(from: segments).enumerated() {
            output += "\(index + 1)\n"
            output += "\(timestamp(cue.start, millisecondSeparator: ",")) --> "
            output += "\(timestamp(cue.end, millisecondSeparator: ","))\n\(cue.text)\n\n"
        }
        return output
    }

    public static func plainText(_ segments: [CaptionSegment]) -> String {
        segments.map(\.text).joined(separator: " ")
    }
}
