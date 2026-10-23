import Foundation

/// The editable fields in the Info tab that the on-device model can write.
public enum MetadataField: String, CaseIterable, Sendable {
    case title, summary, tags, notes

    public var label: String { rawValue.capitalized }
}

/// Prompts for writing one field from a transcript, and cleanup of what the model replies.
/// The model is asked for just the text, but replies often add labels, quotes or bullets.
public enum MetadataPrompt {
    public static let instructions = """
        You help organize screen recordings used for team walkthroughs, demos, and bug reports. \
        Use only what the transcript says. Do not invent details. \
        Reply with only the requested text: no preface, no label, no explanation.
        """

    public static func request(_ field: MetadataField) -> String {
        switch field {
        case .title: "Write a specific title of at most eight words. No quotes and no trailing period."
        case .summary: "Write two or three plain sentences saying what the recording shows or decides."
        case .tags: "List three to six short lowercase tags of one or two words each, separated by commas."
        case .notes:
            "List the action items, decisions and follow-ups that are mentioned, one per line, each starting with \"- \". If there are none, reply exactly: None"
        }
    }

    public static func prompt(for field: MetadataField, transcript: String) -> String {
        request(field) + "\n\nTranscript of a screen recording:\n\n" + SummaryPrompt.clipped(transcript)
    }

    /// Turns a raw model reply into text that is ready to put in the field.
    public static func clean(_ reply: String, for field: MetadataField) -> String {
        let text = stripLabel(reply, field: field).trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .title:
            return SummaryPrompt.cleanedTitle(text.split(separator: "\n").first.map(String.init) ?? "")
        case .summary:
            return text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”")).trimmingCharacters(in: .whitespacesAndNewlines)
        case .tags:
            return TakeMetadata.parseTags(
                text.split(whereSeparator: { $0 == "," || $0 == "\n" }).map {
                    String($0).trimmingCharacters(in: CharacterSet(charactersIn: "#-•* \t\"“”.")).lowercased()
                }.joined(separator: ",")
            ).prefix(6).joined(separator: ", ")
        case .notes:
            let lowered = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            if lowered.isEmpty || lowered == "none" { return "" }
            return text.split(separator: "\n").map { line -> String in
                let body = String(line).trimmingCharacters(in: CharacterSet(charactersIn: "-•* \t"))
                return "- " + body
            }.filter { $0 != "- " }.prefix(8).joined(separator: "\n")
        }
    }

    private static func stripLabel(_ reply: String, field: MetadataField) -> String {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        for label in [field.rawValue, field.label, field.rawValue.uppercased()] {
            for separator in [":", " -"] where trimmed.hasPrefix(label + separator) {
                return String(trimmed.dropFirst(label.count + separator.count))
            }
        }
        return trimmed
    }
}
