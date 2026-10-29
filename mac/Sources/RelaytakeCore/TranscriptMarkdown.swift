import Foundation

/// A take's transcript as a Markdown file: title, summary, then each line with its time, under chapter headings.
public enum TranscriptMarkdown {
    public static func markdown(
        title: String, created: Date, duration: Double?, summary: String, tags: [String],
        transcript: [CaptionSegment], chapters: [Chapter], language: String? = nil
    ) -> String {
        var out = "# \(title.isEmpty ? "Transcript" : title)\n\n"
        var facts = [created.formatted(date: .long, time: .shortened)]
        if let duration, duration > 0 { facts.append(AgentBrief.clock(duration)) }
        if let language { facts.append("Translated: \(language)") }
        out += facts.joined(separator: " · ") + "\n"
        if !tags.isEmpty { out += "\nTags: " + tags.joined(separator: ", ") + "\n" }
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { out += "\n## Summary\n\n\(trimmed)\n" }
        out += "\n## Transcript\n"
        let marks = chapters.sorted { $0.start < $1.start }
        var next = 0
        for segment in transcript {
            while next < marks.count, marks[next].start <= segment.start + 0.05 {
                out += "\n### \(marks[next].title)\n"
                next += 1
            }
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            out += "\n**[\(AgentBrief.clock(segment.start))]** \(text)\n"
        }
        return out
    }
}
