import Foundation

/// A named point in a recording where a new part begins. A chapter runs until the next one starts.
public struct Chapter: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// Seconds into the video.
    public var start: TimeInterval
    public var title: String

    public init(id: UUID = UUID(), start: TimeInterval, title: String) {
        self.id = id
        self.start = start
        self.title = title
    }

    private enum CodingKeys: String, CodingKey { case id, start, title }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        start = try c.decode(TimeInterval.self, forKey: .start)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    }
}

/// Keeping a person's chapters tidy, finding the one being played, and writing them as a list of timestamps.
public enum ChapterList {
    /// Chapters closer together than this are the same moment.
    public static let minimumSpacing: TimeInterval = 1

    /// In time order, with starts inside the recording, no two starts within a second of each other (the earlier one
    /// stays), and every chapter named ("Chapter 3" when the title was left blank).
    public static func normalized(_ chapters: [Chapter], duration: TimeInterval? = nil) -> [Chapter] {
        let ordered = chapters.enumerated()
            .filter { $0.element.start.isFinite }
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
        var result: [Chapter] = []
        for var chapter in ordered {
            chapter.start = max(0, chapter.start)
            if let duration, duration > 0, chapter.start >= duration - minimumSpacing { continue }
            if let last = result.last, chapter.start - last.start < minimumSpacing { continue }
            let title = chapter.title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            chapter.title = title.isEmpty ? "Chapter \(result.count + 1)" : title
            result.append(chapter)
        }
        return result
    }

    /// The chapter playing at `time`: the last one that has started. Nil before the first chapter.
    public static func activeIndex(in chapters: [Chapter], at time: TimeInterval) -> Int? {
        chapters.lastIndex { $0.start <= time + 0.05 }
    }

    /// "0:00 Intro", one chapter per line: the form video sites read chapters from a description.
    public static func timestampList(_ chapters: [Chapter]) -> String {
        chapters.map { "\(timestamp($0.start)) \($0.title)" }.joined(separator: "\n")
    }

    /// "4:07", or "1:02:09" from an hour on.
    public static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

extension ChapterList {
    /// The chapters of a recording as they stand in a copy with parts cut out. A chapter begins at the first of its
    /// own footage that survived, so one whose opening was cut starts where its remaining footage does. A chapter
    /// left with less than a second is dropped; its few remaining moments play under the chapter before it.
    public static func remapped(_ chapters: [Chapter], through cuts: EditModel) -> [Chapter] {
        let ordered = normalized(chapters)
        var result: [Chapter] = []
        for (index, chapter) in ordered.enumerated() {
            let end = index + 1 < ordered.count ? ordered[index + 1].start : max(cuts.duration, chapter.start)
            let kept = cuts.outputSpans(forSource: TimeSpan(start: chapter.start, end: end))
            guard let first = kept.map(\.start).min(), kept.reduce(0, { $0 + $1.length }) >= minimumSpacing else { continue }
            var moved = chapter
            moved.start = first
            result.append(moved)
        }
        return normalized(result, duration: cuts.keptDuration)
    }
}

/// Finds where a recording changes subject, from its transcript. This is arithmetic on the words and the timing,
/// so the same transcript always gives the same chapters. The result is a proposal: the person decides what to keep.
///
/// Three signals are combined at each place a line begins:
///  - the words just before and just after share few of their subject words (a change of subject),
///  - there is a pause before the line,
///  - the line opens the way a speaker opens a new part ("Next, let's look at…", "Finally…").
/// The wording is the main evidence. A pause or a signpost phrase alone never starts a chapter, because people
/// stop to think and say "next" mid-explanation. The thresholds are cautious judgments checked against made-up
/// transcripts, not tuned on real recordings: it is better to miss a chapter, which is one click to add, than to
/// propose one that is not there.
public enum ChapterDetector {
    /// A recording shorter than this is not worth dividing.
    public static let minimumRecording: TimeInterval = 90
    /// The least evidence, 0...1, that a place starts a chapter, and the least of it that must come from the words:
    /// a pause and a signpost phrase can tip a close call but cannot make a chapter on their own.
    static let minimumScore = 0.5
    static let minimumWording = 0.35
    static let minimumLines = 6

    /// Chapters for `segments`, the first always at 0:00. Empty when the recording is short, has too little speech,
    /// or has no clear change of subject. Each title is a few of the section's own distinctive words; the app
    /// replaces them with better ones from the on-device model when it can.
    public static func detect(segments: [CaptionSegment], duration: TimeInterval) -> [Chapter] {
        let lines = segments
            .filter { $0.end >= $0.start && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
        let length = max(duration, lines.last?.end ?? 0)
        guard length >= minimumRecording, lines.count >= minimumLines else { return [] }

        let minLength = min(120, max(30, length / 12))
        let target = min(12, max(2, Int((length / 150).rounded())))
        let candidates = boundaryScores(lines: lines, length: length, minLength: minLength)

        // Best first, but never two chapters closer than `minLength`, and only as many as the length calls for.
        var chosen: [(index: Int, time: TimeInterval)] = []
        for candidate in candidates.sorted(by: { ($1.score, $0.time) < ($0.score, $1.time) }) {
            guard candidate.score >= minimumScore, chosen.count < target - 1 else { break }
            guard candidate.wording >= minimumWording else { continue }
            guard !chosen.contains(where: { abs($0.time - candidate.time) < minLength }) else { continue }
            chosen.append((candidate.index, candidate.time))
        }
        guard !chosen.isEmpty else { return [] }
        chosen.sort { $0.time < $1.time }

        // A chapter begins a breath before its first word, never inside the line before.
        var starts: [TimeInterval] = [0]
        for pick in chosen { starts.append(max(lines[pick.index - 1].end, pick.time - 0.4)) }
        var chapters = starts.map { Chapter(start: $0, title: "") }
        let names = fallbackTitles(for: sections(of: lines, chapters: chapters), allLines: lines)
        for index in chapters.indices { chapters[index].title = names[index] }
        return chapters
    }

    /// How strongly each line start looks like the start of a new part, 0...1.
    ///
    /// The wording signal compares four stretches of speech of equal length around the place: two before (A, B) and
    /// two after (C, D). If B and C share fewer subject words than A and B do, and than C and D do, the subject
    /// changed there. Judging the change against how much each side holds together means a speaker who simply uses
    /// a wide vocabulary does not look like a series of changes.
    static func boundaryScores(lines: [CaptionSegment], length: TimeInterval, minLength: TimeInterval)
        -> [(index: Int, time: TimeInterval, score: Double, wording: Double)]
    {
        let window = min(45, max(20, length / 20))
        let counts = lines.map { termCounts($0.text) }
        let starts = lines.map(\.start)
        /// The first line starting at or after `time`.
        func lowerBound(_ time: TimeInterval) -> Int {
            var (lo, hi) = (0, starts.count)
            while lo < hi {
                let mid = (lo + hi) / 2
                if starts[mid] < time { lo = mid + 1 } else { hi = mid }
            }
            return lo
        }
        func words(_ from: TimeInterval, _ to: TimeInterval) -> [String: Double] {
            var total: [String: Double] = [:]
            for i in lowerBound(from)..<lowerBound(to) { add(counts[i], to: &total) }
            return total
        }

        var wording: [(index: Int, time: TimeInterval, contrast: Double)] = []
        for b in 1..<lines.count {
            let time = lines[b].start
            guard time >= minLength, length - time >= minLength else { continue }
            let (a, before, after, d) = (
                words(time - 2 * window, time - window), words(time - window, time),
                words(time, time + window), words(time + window, time + 2 * window))
            guard !before.isEmpty, !after.isEmpty else { continue }
            // A side with nothing beyond the window (the start or end of the recording) has no cohesion to compare.
            let cohesion = [a.isEmpty ? nil : cosine(a, before), d.isEmpty ? nil : cosine(after, d)].compactMap { $0 }
            guard !cohesion.isEmpty else { continue }
            wording.append((b, time, cohesion.reduce(0, +) / Double(cohesion.count) - cosine(before, after)))
        }

        // A real change of subject lifts the contrast across a stretch of neighbouring line starts; chance does not.
        // Averaging over a third of a window keeps the first and drops the second.
        let reach = window / 3
        var scores: [(index: Int, time: TimeInterval, score: Double, wording: Double)] = []
        var low = 0
        for (position, candidate) in wording.enumerated() {
            while wording[low].time < candidate.time - reach { low += 1 }
            var high = position
            while high + 1 < wording.count, wording[high + 1].time <= candidate.time + reach { high += 1 }
            let near = wording[low...high]
            let smooth = near.reduce(0) { $0 + $1.contrast } / Double(near.count)
            let pause = min(1, max(0, candidate.time - lines[candidate.index - 1].end) / 4)
            let cue = opensNewPart(lines[candidate.index].text) ? 1.0 : 0.0
            let wordingScore = 0.65 * min(1, max(0, smooth / 0.6))
            scores.append((candidate.index, candidate.time, wordingScore + 0.2 * pause + 0.15 * cue, wordingScore))
        }
        return scores
    }

    /// The transcript lines in each chapter: a line belongs to the last chapter that began at or before it.
    public static func sections(of segments: [CaptionSegment], chapters: [Chapter]) -> [[CaptionSegment]] {
        var result = Array(repeating: [CaptionSegment](), count: chapters.count)
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            guard let index = chapters.lastIndex(where: { $0.start <= segment.start + 0.05 }) ?? chapters.indices.first
            else { continue }
            result[index].append(segment)
        }
        return result
    }

    // MARK: Words

    static let stopwords: Set<String> = [
        "about", "actually", "after", "again", "all", "also", "and", "any", "are", "because", "been", "before", "being",
        "bit", "but", "can", "could", "did", "does", "doing", "don't", "down", "each", "even", "for", "from", "get",
        "going", "gonna", "got", "had", "has", "have", "having", "her", "here", "him", "his", "how", "i'd", "i'll",
        "i'm", "i've", "into", "it's", "its", "just", "kind", "know", "let", "let's", "like", "little", "look", "lot",
        "make", "more", "most", "much", "need", "not", "now", "off", "okay", "once", "one", "only", "other", "our",
        "out", "over", "really", "right", "same", "see", "she", "should", "show", "some", "sort", "such", "than",
        "that", "that's", "the", "their", "them", "then", "there", "there's", "these", "they", "they're", "thing",
        "things", "think", "this", "those", "through", "too", "under", "until", "very", "want", "was", "way", "we'll",
        "we're", "well", "were", "what", "what's", "when", "where", "which", "while", "who", "why", "will", "with",
        "would", "yeah", "you", "you'll", "you're", "your",
    ]

    /// The subject words of a line: three letters or more, no filler, no bare numbers.
    static func contentWords(_ text: String) -> [String] {
        RestartFinder.words(text).filter { $0.count >= 3 && !stopwords.contains($0) && !$0.allSatisfy(\.isNumber) }
    }

    private static func termCounts(_ text: String) -> [String: Double] {
        contentWords(text).reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private static func add(_ counts: [String: Double], to total: inout [String: Double]) {
        for (word, count) in counts { total[word, default: 0] += count }
    }

    /// 1 for the same words in the same proportion, 0 for nothing in common. No words at all counts as nothing in
    /// common: there is no evidence the subject continues.
    private static func cosine(_ a: [String: Double], _ b: [String: Double]) -> Double {
        let (small, large) = a.count <= b.count ? (a, b) : (b, a)
        var dot = 0.0
        for (word, count) in small { dot += count * (large[word] ?? 0) }
        let normA = a.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        let normB = b.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return normA > 0 && normB > 0 ? dot / (normA * normB) : 0
    }

    // MARK: Signposts

    private static let leadingFiller: Set<String> = ["okay", "ok", "alright", "all", "right", "so", "and", "now", "well"]
    private static let signposts: [[String]] = [
        ["moving", "on"], ["next"], ["let's", "move"], ["let's", "talk", "about"], ["let's", "look", "at"],
        ["let's", "go", "to"], ["let's", "switch"], ["let's", "start"], ["let's", "begin"], ["on", "to"], ["onto"],
        ["finally"], ["lastly"], ["last", "thing"], ["in", "conclusion"], ["to", "wrap", "up"], ["to", "summarize"],
        ["to", "sum", "up"], ["first", "of", "all"], ["second"], ["third"], ["another", "thing"],
        ["the", "next"], ["the", "last"], ["the", "final"],
    ]

    /// Whether a line opens the way a speaker starts a new part, after any "okay, so".
    static func opensNewPart(_ text: String) -> Bool {
        var words = RestartFinder.words(text)[...]
        while let first = words.first, leadingFiller.contains(first) { words = words.dropFirst() }
        return signposts.contains { words.starts(with: $0) }
    }

    // MARK: Fallback titles

    /// A name for each section made only from its own words: the ones it uses most that the recording as a whole
    /// uses least. Good enough to tell parts apart until a better title comes along.
    static func fallbackTitles(for sections: [[CaptionSegment]], allLines: [CaptionSegment]) -> [String] {
        var linesWithWord: [String: Int] = [:]
        for line in allLines { for word in Set(contentWords(line.text)) { linesWithWord[word, default: 0] += 1 } }
        let total = Double(max(1, allLines.count))
        return sections.enumerated().map { number, lines in
            var used: [String: Double] = [:]
            for line in lines { for word in contentWords(line.text) { used[word, default: 0] += 1 } }
            let ranked = used
                .map { word, count in (word: word, score: count * log((total + 1) / (Double(linesWithWord[word] ?? 1) + 0.5))) }
                .sorted { ($1.score, $0.word) < ($0.score, $1.word) }
                .prefix(3)
            guard !ranked.isEmpty else { return "Part \(number + 1)" }
            return ranked.map { $0.word.prefix(1).uppercased() + $0.word.dropFirst() }.joined(separator: ", ")
        }
    }
}

/// Asks the language model to name one section of a transcript. It names; it never chooses where a chapter starts.
public enum ChapterPrompt {
    /// The on-device model has a small context window, so a long section keeps its start and end.
    public static let maxCharacters = 2500

    public static let instructions = """
        You name one section of a screen recording from its transcript, for a list of chapters. \
        Use only what the transcript says. Do not invent details. \
        Reply with the chapter title only: at most six words, no quotes, no label, no trailing period.
        """

    public static func prompt(for section: [CaptionSegment], number: Int, of count: Int) -> String {
        var text = section.map(\.text).joined(separator: " ")
        if text.count > maxCharacters {
            let half = maxCharacters / 2
            text = String(text.prefix(half)) + " […] " + String(text.suffix(half))
        }
        return "Section \(number) of \(count) of a screen recording. Transcript of this section:\n\n\(text)"
    }

    /// The title from a reply, or nil when there is nothing usable (empty, or a paragraph instead of a title).
    public static func parse(_ reply: String) -> String? {
        guard let line = reply.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty })
        else { return nil }
        var text = line.trimmingCharacters(in: CharacterSet(charactersIn: "-•*# \t"))
        // "Title: Setting up billing" / "Chapter 2: Setting up billing"
        if let colon = text.firstIndex(of: ":") {
            let label = text[..<colon].lowercased()
            if label == "title" || label.hasPrefix("chapter") || label.hasPrefix("section") {
                text = String(text[text.index(after: colon)...])
            }
        }
        let title = SummaryPrompt.cleanedTitle(text)
        guard !title.isEmpty, title.split(whereSeparator: \.isWhitespace).count <= 10 else { return nil }
        return title
    }
}

extension TakeLibrary {
    /// Saves a take's chapters, tidied (see `ChapterList.normalized`), and returns what was saved.
    @discardableResult
    public static func saveChapters(_ chapters: [Chapter], for entry: TakeEntry, duration: TimeInterval? = nil) throws -> [Chapter] {
        let known = duration ?? metadata(for: entry.files)?.durationSeconds
        let tidy = ChapterList.normalized(chapters, duration: known)
        try update(entry) { $0.chapters = tidy }
        return tidy
    }
}

extension TakeLibrary {
    /// Saves chapters into the notes beside a take that has no entry yet (a copy just rendered), keeping anything
    /// already written there.
    /// `chaptersEnabled` carries the original's own choice to show or hide chapters; nil leaves the copy on the default.
    public static func saveChapters(
        _ chapters: [Chapter], to files: TakeFiles, created: Date, duration: TimeInterval?, chaptersEnabled: Bool? = nil
    ) throws {
        var metadata = Self.metadata(for: files) ?? TakeMetadata(title: "", summary: "", created: created)
        metadata.chapters = ChapterList.normalized(chapters, duration: duration ?? metadata.durationSeconds)
        if let chaptersEnabled { metadata.chaptersEnabled = chaptersEnabled }
        try metadata.encoded().write(to: files.metadata, options: .atomic)
    }
}
