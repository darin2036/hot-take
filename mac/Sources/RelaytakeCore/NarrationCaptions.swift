import Foundation

// A demo can have no spoken audio and still be understood: the agent writes what each step shows, and that text becomes captions
// drawn into the picture, a `.vtt` file, and the take's transcript (so search, summaries and chapters work too). The words are the
// agent's, shown on screen; nothing is spoken or recognised, and nothing leaves this Mac. The timing is the narration script's: each
// line fills the part of the edited video that begins at its marker.

public enum NarrationCaptions {
    /// A short breath before a line appears and after it ends, so captions do not butt up against the next step.
    public static let lead = 0.3
    public static let tail = 0.3

    /// Sentences of a line, each kept with its end punctuation. A line with none is one sentence.
    public static func sentences(of text: String) -> [String] {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return [] }
        var result: [String] = []
        var current = ""
        let characters = Array(collapsed)
        for (index, character) in characters.enumerated() {
            current.append(character)
            let atEnd = index == characters.count - 1
            let nextIsSpace = !atEnd && characters[index + 1] == " "
            if ".!?".contains(character), atEnd || nextIsSpace {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    /// Caption lines on the *edited* video: for each part with narration, its sentences share the part's time (less a short lead
    /// and tail) in proportion to their length.
    public static func editedCues(beats: [NarrationBeat]) -> [CaptionSegment] {
        var cues: [CaptionSegment] = []
        for beat in beats {
            let lines = sentences(of: beat.text ?? "")
            guard !lines.isEmpty, beat.length > 0 else { continue }
            var start = beat.start + min(lead, beat.length * 0.1)
            var end = beat.end - min(tail, beat.length * 0.1)
            if end - start < 0.5 { start = beat.start; end = beat.end }
            let weights = lines.map { Double(max(1, $0.count)) }
            let total = weights.reduce(0, +)
            var cursor = start
            for (line, weight) in zip(lines, weights) {
                let next = cursor + (end - start) * weight / total
                cues.append(CaptionSegment(start: cursor, end: next, text: line))
                cursor = next
            }
        }
        return cues
    }

    /// The same lines in the *original's* time, which is how the Studio keeps captions so a later cut takes its captions with it.
    public static func sourceCues(beats: [NarrationBeat], cuts: EditModel) -> [CaptionSegment] {
        editedCues(beats: beats).compactMap { cue in
            let spans = cuts.sourceSpans(forOutput: TimeSpan(start: cue.start, end: cue.end))
            guard let first = spans.first, let last = spans.last, last.end > first.start else { return nil }
            return CaptionSegment(start: first.start, end: last.end, text: cue.text)
        }
    }

    /// The transcript of a project whose captions came from narration: its caption lines on the edited video, in order. Empty if the
    /// captions were not narration (they would be a real transcript, which is made another way).
    public static func transcript(for project: StudioProject) -> [CaptionSegment] {
        guard let captions = project.captions, captions.fromNarration == true else { return [] }
        return captions.cues.compactMap { cue in
            let spans = project.cuts.outputSpans(forSource: TimeSpan(start: cue.start, end: cue.end))
            guard let first = spans.first, let last = spans.last, last.end - first.start >= 0.1 else { return nil }
            return CaptionSegment(start: first.start, end: last.end, text: cue.text)
        }
        .sorted { $0.start < $1.start }
    }
}
