import Foundation

// "Bug Report": a take turned into a ticket for a person: a title, a short description, steps to reproduce with a
// picture on each step, and what was expected and what happened. It is a draft the person edits, then copies as
// text for Jira, Slack, GitHub or a service desk and attaches the pictures (and the recording) themselves. It
// shares its pictures and folder handling with the agent request (`AgentBrief`) and is made on this Mac; nothing
// is sent anywhere.

public enum BugReport {
    /// One step to reproduce, and the number (from 1) of the picture that shows it, if any.
    public struct Step: Codable, Equatable, Identifiable, Sendable {
        public var id = UUID()
        public var text: String
        public var picture: Int?

        public init(text: String, picture: Int? = nil) {
            self.text = text
            self.picture = picture
        }

        private enum CodingKeys: String, CodingKey { case text, picture }
    }

    /// The ticket as the person sees and edits it. Empty parts are left out of the text.
    public struct Draft: Codable, Equatable, Sendable {
        public var title: String
        public var summary: String
        public var steps: [Step]
        public var expected: String
        public var actual: String
        public var environment: String

        public init(
            title: String = "", summary: String = "", steps: [Step] = [], expected: String = "", actual: String = "",
            environment: String = ""
        ) {
            self.title = title
            self.summary = summary
            self.steps = steps
            self.expected = expected
            self.actual = actual
            self.environment = environment
        }
    }

    /// What the narration says about the bug as a whole, as the on-device model read it. Empty parts were not stated.
    public struct Reading: Equatable, Sendable {
        public var title: String
        public var summary: String
        public var expected: String
        public var actual: String

        public init(title: String, summary: String, expected: String, actual: String) {
            self.title = title
            self.summary = summary
            self.expected = expected
            self.actual = actual
        }
    }

    /// Where the text is going; each place writes bold, headings and lists its own way.
    public enum Format: String, CaseIterable, Identifiable, Sendable {
        case markdown, jira, slack, plain
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .markdown: "Markdown"
            case .jira: "Jira"
            case .slack: "Slack"
            case .plain: "Plain text"
            }
        }
        /// Where it pastes well.
        public var detail: String {
            switch self {
            case .markdown: "GitHub, Linear, Jira Cloud, most service desks"
            case .jira: "Jira Server and Data Center (wiki markup)"
            case .slack: "Slack and chat; the title leads the message"
            case .plain: "Email and anywhere else"
            }
        }
    }

    public static let fileName = "BUG-REPORT.md"
    public static let draftFileName = "bug-report.json"

    // MARK: Text

    /// "02-0m03s.png" for each moment, the names the pictures are saved under.
    public static func pictureNames(for moments: [AgentBrief.Moment]) -> [String] {
        moments.enumerated().map { AgentBrief.pictureName(number: $0.offset + 1, of: moments.count, time: $0.element.time) }
    }

    /// The text to paste into the ticket or message. A ticket has its own title field, so only Slack (and the saved
    /// Markdown file) put the title in the text. A step with a picture names the file to attach.
    public static func text(of draft: Draft, format: Format, pictures: [String], includeTitle: Bool? = nil) -> String {
        func heading(_ name: String) -> String {
            switch format {
            case .markdown: "## \(name)"
            case .jira: "h3. \(name)"
            case .slack: "*\(name)*"
            case .plain: "\(name):"
            }
        }
        func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var blocks: [String] = []
        let title = clean(draft.title)
        if includeTitle ?? (format == .slack), !title.isEmpty {
            switch format {
            case .markdown: blocks.append("# \(title)")
            case .jira: blocks.append("h2. \(title)")
            case .slack: blocks.append("*\(title)*")
            case .plain: blocks.append(title)
            }
        }
        if !clean(draft.summary).isEmpty { blocks.append(clean(draft.summary)) }
        let steps = draft.steps.filter { !clean($0.text).isEmpty }
        if !steps.isEmpty {
            let lines = steps.enumerated().map { index, step -> String in
                var line = clean(step.text)
                if let picture = step.picture, picture >= 1, picture <= pictures.count { line += " (\(pictures[picture - 1]))" }
                return format == .jira ? "# \(line)" : "\(index + 1). \(line)"
            }
            blocks.append(([heading("Steps to reproduce")] + lines).joined(separator: "\n"))
        }
        for (name, body) in [("Expected", draft.expected), ("Actual", draft.actual), ("Environment", draft.environment)]
        where !clean(body).isEmpty {
            blocks.append("\(heading(name))\n\(clean(body))")
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    // MARK: Drafting

    /// A step for a moment without the model: the first sentence of what was said around it, kept short.
    public static func fallbackStep(narration: String) -> String {
        let words = narration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return "" }
        let sentence = words.split(whereSeparator: { ".!?".contains($0) }).first.map(String.init) ?? words
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 140 ? String(trimmed.prefix(137)) + "…" : trimmed
    }

    /// The draft for a take: a step and picture for each moment (`steps` holds the model's wording by moment
    /// number from 1; what the person said stands in where it has none), and the model's reading of the rest.
    public static func draft(
        metadata: TakeMetadata, moments: [AgentBrief.Moment], steps: [Int: String], reading: Reading?
    ) -> Draft {
        let said = AgentBrief.narration(for: moments, transcript: metadata.transcript)
        let rows = moments.indices.map { index -> Step in
            let model = steps[index + 1] ?? ""
            let text = steps.isEmpty ? fallbackStep(narration: said[index].map(\.text).joined(separator: " ")) : model
            return Step(text: text, picture: index + 1)
        }
        return Draft(
            title: reading?.title.isEmpty == false ? reading!.title : metadata.title, summary: reading?.summary ?? "",
            steps: rows, expected: reading?.expected ?? "", actual: reading?.actual ?? "")
    }

    // MARK: Files

    /// A draft saved with its folder: the pictures, `BUG-REPORT.md` (the Markdown text) and `bug-report.json` (so
    /// the draft can be reopened and edited).
    public struct Saved: Equatable, Sendable {
        public var folder: URL
        public var draft: Draft
        public var pictureNames: [String]

        public var pictures: [URL] {
            pictureNames.map { folder.appendingPathComponent(AgentBrief.picturesFolder).appendingPathComponent($0) }
        }
        public var markdownFile: URL { folder.appendingPathComponent(BugReport.fileName) }
    }

    private struct Stored: Codable {
        var draft: Draft
        var pictures: [String]
    }

    private static func files(for draft: Draft, pictures: [String]) -> [(name: String, text: String)] {
        let json = (try? JSONEncoder().encode(Stored(draft: draft, pictures: pictures))).flatMap { String(data: $0, encoding: .utf8) }
        return [
            (fileName, text(of: draft, format: .markdown, pictures: pictures, includeTitle: true)),
            (draftFileName, json ?? "{}"),
        ]
    }

    /// Takes the pictures for `plan` and saves the draft with them beside the take (replacing an earlier one). The
    /// folder appears only when complete.
    public static func write(
        for files: TakeFiles, plan: AgentBrief.Plan, draft: Draft,
        fileManager: FileManager = .default, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> Saved {
        let names = pictureNames(for: plan.moments)
        let output = try await AgentBrief.writeFolder(
            for: files, folder: files.bugReportDirectory, plan: plan, fileManager: fileManager, progress: progress
        ) { _ in Self.files(for: draft, pictures: names) }
        return Saved(folder: output.folder, draft: draft, pictureNames: names)
    }

    /// Saves an edited draft over the one in its folder.
    public static func save(_ saved: Saved) throws {
        for file in files(for: saved.draft, pictures: saved.pictureNames) {
            try file.text.write(to: saved.folder.appendingPathComponent(file.name), atomically: true, encoding: .utf8)
        }
    }

    /// The draft saved beside `files`, if it is there and its pictures are too.
    public static func load(for files: TakeFiles, fileManager: FileManager = .default) -> Saved? {
        let folder = files.bugReportDirectory
        guard let data = fileManager.contents(atPath: folder.appendingPathComponent(draftFileName).path),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return nil }
        let saved = Saved(folder: folder, draft: stored.draft, pictureNames: stored.pictures)
        return saved.pictures.allSatisfy { fileManager.fileExists(atPath: $0.path) } ? saved : nil
    }
}

/// Asking the on-device model what a bug report's narration says, and reading its reply.
public enum BugReportPrompt {
    public static let instructions = """
        You turn the narration of a screen recording that shows a software bug into the start of a bug ticket. \
        Use only what the transcript says. Do not invent error messages, versions, or details. \
        If the transcript does not say something, write "Not stated" for that part. \
        Reply in exactly this format and nothing else:
        TITLE: <a short ticket title, under ten words>
        SUMMARY: <one or two sentences saying what is wrong and where>
        EXPECTED: <what should have happened>
        ACTUAL: <what happened instead>
        """

    public static func prompt(transcript: String) -> String {
        "Transcript of a screen recording:\n\n\(SummaryPrompt.clipped(transcript))"
    }

    private enum Field { case title, summary, expected, actual }

    /// Reads the TITLE:/SUMMARY:/EXPECTED:/ACTUAL: reply. A field may run over several lines; "Not stated" and
    /// "None" count as empty. Nil when nothing usable came back.
    public static func parse(_ reply: String) -> BugReport.Reading? {
        var text: [Field: [String]] = [:]
        var current: Field?
        let labels: [(String, Field)] = [("TITLE:", .title), ("SUMMARY:", .summary), ("EXPECTED:", .expected), ("ACTUAL:", .actual)]
        for line in reply.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
            let upper = line.uppercased()
            if let (label, field) = labels.first(where: { upper.hasPrefix($0.0) }) {
                current = field
                let rest = String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { text[field, default: []].append(rest) }
            } else if let current {
                text[current, default: []].append(line)
            }
        }
        func field(_ f: Field) -> String {
            let value = (text[f] ?? []).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\"“” *"))
            return isUnstated(value) ? "" : value
        }
        let reading = BugReport.Reading(title: field(.title), summary: field(.summary), expected: field(.expected), actual: field(.actual))
        return reading.title.isEmpty && reading.summary.isEmpty && reading.expected.isEmpty && reading.actual.isEmpty
            ? nil : reading
    }

    static func isUnstated(_ value: String) -> Bool {
        let key = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        return key.isEmpty || key == "none" || key == "not stated" || key == "n/a" || key == "skip"
    }

    /// The readings from each part of a long recording, laid out so one more pass can merge them.
    public static func mergeText(_ readings: [BugReport.Reading]) -> String {
        readings.enumerated().map { index, reading in
            "Part \(index + 1) of the recording. Title: \(reading.title)\nSummary: \(reading.summary)\n"
                + "Expected: \(reading.expected)\nActual: \(reading.actual)"
        }.joined(separator: "\n\n")
    }

    /// Joins readings without asking the model: the first non-empty of each part.
    public static func combined(_ readings: [BugReport.Reading]) -> BugReport.Reading? {
        guard !readings.isEmpty else { return nil }
        return BugReport.Reading(
            title: readings.map(\.title).first { !$0.isEmpty } ?? "",
            summary: readings.map(\.summary).first { !$0.isEmpty } ?? "",
            expected: readings.map(\.expected).first { !$0.isEmpty } ?? "",
            actual: readings.map(\.actual).first { !$0.isEmpty } ?? "")
    }

    // MARK: Steps

    public static let stepInstructions = """
        You write the steps to reproduce a software bug from what a person said while recording their screen. \
        You get numbered moments, each with the words spoken around it and whether they clicked. \
        For each moment write one short step in the imperative, such as "Click Save" or "Open the Orders page", \
        saying what the person did, using only what they said. \
        If the moment is the person explaining the problem or what they expected, and not something they did, write SKIP. \
        Reply with one line per moment in exactly this format and nothing else:
        1: <step or SKIP>
        2: <step or SKIP>
        """

    /// Each moment's line for the model: its number, whether it was a click, and the words said around it.
    public static func stepLine(number: Int, clicked: Bool, narration: String, limit: Int = 300) -> String {
        let words = narration.trimmingCharacters(in: .whitespacesAndNewlines)
        let said = words.count > limit ? String(words.prefix(limit)) + "…" : words
        return "\(number) (\(clicked ? "clicked" : "talking")): \(said.isEmpty ? "(nothing said)" : said)"
    }

    /// Groups of consecutive lines that each fit the model's window.
    public static func stepBatches(_ lines: [String], maxCharacters: Int = SummaryPrompt.maxCharacters) -> [Range<Int>] {
        var batches: [Range<Int>] = []
        var start = 0
        var size = 0
        for (index, line) in lines.enumerated() {
            if index > start, size + line.count + 1 > maxCharacters {
                batches.append(start..<index)
                start = index
                size = 0
            }
            size += line.count + 1
        }
        if start < lines.count { batches.append(start..<lines.count) }
        return batches
    }

    /// Reads "3: Click Save" lines into step wording by moment number. SKIP and blank lines give no entry.
    public static func parseSteps(_ reply: String) -> [Int: String] {
        var steps: [Int: String] = [:]
        for line in reply.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let digits = line.prefix { $0.isNumber }
            guard let number = Int(digits), let after = line.dropFirst(digits.count).first, after == ":" || after == "." || after == ")"
            else { continue }
            let text = line.dropFirst(digits.count + 1).trimmingCharacters(in: CharacterSet(charactersIn: " \"“”*"))
            if !isUnstated(text), steps[number] == nil { steps[number] = text }
        }
        return steps
    }
}
