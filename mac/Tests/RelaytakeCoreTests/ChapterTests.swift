import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct ChapterTests {
    private let billing = ["billing", "invoice", "customer", "payment", "subscription", "refund", "receipt", "plan"]
    private let editor = ["timeline", "clip", "trim", "waveform", "caption", "export", "preview", "render"]
    private let hiring = ["candidate", "interview", "resume", "offer", "recruiter", "salary", "referral", "panel"]

    /// Lines of about five seconds each about one subject, from `start` for `seconds`. Every line mentions three of
    /// the subject's words, so neighbouring lines share vocabulary the way a real explanation does.
    private func talk(_ words: [String], from start: Double, for seconds: Double, gap: Double = 0.4, opening: String? = nil) -> [CaptionSegment] {
        var lines: [CaptionSegment] = []
        var time = start
        var n = 0
        while time + 5 <= start + seconds {
            let picked = (0..<3).map { words[(n + $0 * 2) % words.count] }
            let text = n == 0 && opening != nil ? opening! + " " + picked.joined(separator: " and ") : "so the \(picked[0]) and the \(picked[1]) with the \(picked[2])"
            lines.append(CaptionSegment(start: time, end: time + 5 - gap, text: text))
            time += 5
            n += 1
        }
        return lines
    }

    // MARK: Detection

    @Test func aChangeOfSubjectStartsAChapterNearIt() {
        let lines = talk(billing, from: 0, for: 150) + talk(editor, from: 150, for: 150)
        let chapters = ChapterDetector.detect(segments: lines, duration: 300)
        #expect(chapters.count == 2)
        #expect(chapters[0].start == 0)
        #expect(abs(chapters[1].start - 150) < 10)
    }

    @Test func threeSubjectsGiveThreeChaptersInOrder() {
        let lines = talk(billing, from: 0, for: 200) + talk(editor, from: 200, for: 200) + talk(hiring, from: 400, for: 200)
        let chapters = ChapterDetector.detect(segments: lines, duration: 600)
        #expect(chapters.count == 3)
        #expect(chapters.map(\.start) == chapters.map(\.start).sorted())
        #expect(abs(chapters[1].start - 200) < 10)
        #expect(abs(chapters[2].start - 400) < 10)
    }

    @Test func aPauseAndAnOpeningPhraseHelpButAreNotEnoughAlone() {
        // One subject throughout, with a long pause and "next" in the middle: still one chapter.
        var lines = talk(billing, from: 0, for: 140)
        lines += talk(billing, from: 150, for: 150, opening: "Next let's talk about")
        #expect(ChapterDetector.detect(segments: lines, duration: 300).isEmpty)
    }

    @Test func aSignpostAndPauseMakeAClearButModestShiftEnough() {
        // Subjects that share some words (billing and plans) with a pause and "next" at the change.
        let overlap = ["billing", "invoice", "plan", "upgrade", "tier", "seats", "limit", "trial"]
        var lines = talk(billing, from: 0, for: 140)
        lines += talk(overlap, from: 145, for: 155, opening: "Next let's look at")
        let chapters = ChapterDetector.detect(segments: lines, duration: 300)
        #expect(chapters.count == 2)
        #expect(abs(chapters[1].start - 145) < 10)
    }

    @Test func oneSubjectThroughoutHasNoChapters() {
        let lines = talk(billing, from: 0, for: 600)
        #expect(ChapterDetector.detect(segments: lines, duration: 600).isEmpty)
    }

    /// A repeatable stand-in for chance, so a noisy transcript is the same on every run.
    private struct Chance {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    /// Speech with a wide vocabulary: every line draws `own` words from the subject's list and `stray` from `others`.
    private func noisyTalk(
        _ words: [String], others: [String], from start: Double, for seconds: Double, own: Int = 3, stray: Int = 1, seed: UInt64
    ) -> [CaptionSegment] {
        var chance = Chance(state: seed)
        var lines: [CaptionSegment] = []
        var time = start
        while time + 6 <= start + seconds {
            let picked = (0..<own).map { _ in words[chance.next(words.count)] } + (0..<stray).map { _ in others[chance.next(others.count)] }
            lines.append(CaptionSegment(start: time, end: time + 5, text: "so the " + picked.joined(separator: " and the ")))
            time += 6
        }
        return lines
    }

    @Test func aWideVocabularyOnOneSubjectDoesNotInventChapters() {
        let wide = billing + editor  // one long talk that happens to use sixteen subject words
        for seed in 1...20 as ClosedRange<UInt64> {
            let lines = noisyTalk(wide, others: hiring, from: 0, for: 600, seed: seed)
            #expect(ChapterDetector.detect(segments: lines, duration: 600).isEmpty, "seed \(seed)")
        }
    }

    @Test func aChangeOfSubjectIsFoundThroughStrayWords() {
        // One word in ten comes from the other subject, so the two sides overlap a little.
        for seed in 1...20 as ClosedRange<UInt64> {
            let lines = noisyTalk(billing, others: editor, from: 0, for: 300, own: 9, seed: seed)
                + noisyTalk(editor, others: billing, from: 300, for: 300, own: 9, seed: seed + 100)
            let chapters = ChapterDetector.detect(segments: lines, duration: 600)
            #expect(chapters.count == 2, "seed \(seed)")
            if chapters.count == 2 { #expect(abs(chapters[1].start - 300) < 20, "seed \(seed)") }
        }
    }

    @Test func aShortRecordingIsNotDivided() {
        let lines = talk(billing, from: 0, for: 40) + talk(editor, from: 40, for: 40)
        #expect(ChapterDetector.detect(segments: lines, duration: 80).isEmpty)
    }

    @Test func tooLittleSpeechGivesNothing() {
        let lines = [CaptionSegment(start: 0, end: 4, text: "hello there"), CaptionSegment(start: 200, end: 204, text: "bye now")]
        #expect(ChapterDetector.detect(segments: lines, duration: 300).isEmpty)
        #expect(ChapterDetector.detect(segments: [], duration: 300).isEmpty)
    }

    @Test func aChapterIsNeverShorterThanTheMinimum() {
        // Subjects alternating every 20 seconds must not become chapters 20 seconds long.
        var lines: [CaptionSegment] = []
        for block in 0..<12 { lines += talk(block.isMultiple(of: 2) ? billing : editor, from: Double(block) * 20, for: 20) }
        let chapters = ChapterDetector.detect(segments: lines, duration: 240)
        for (a, b) in zip(chapters, chapters.dropFirst()) { #expect(b.start - a.start >= 30) }
        #expect((chapters.last.map { 240 - $0.start } ?? 240) >= 30)
    }

    @Test func theNumberOfChaptersFollowsTheLength() {
        // Six subjects in 10 minutes: at most round(600 / 150) = 4 chapters.
        let subjects = [billing, editor, hiring, ["garden", "tomato", "soil", "water", "seed", "compost", "shade", "bed"],
                        ["engine", "piston", "valve", "torque", "gasket", "cylinder", "fuel", "spark"],
                        ["guitar", "chord", "string", "tuner", "pick", "fret", "strum", "scale"]]
        var lines: [CaptionSegment] = []
        for (n, words) in subjects.enumerated() { lines += talk(words, from: Double(n) * 100, for: 100) }
        let chapters = ChapterDetector.detect(segments: lines, duration: 600)
        #expect(chapters.count >= 2 && chapters.count <= 4)
    }

    @Test func detectionIsRepeatableAndIgnoresInputOrder() {
        let lines = talk(billing, from: 0, for: 150) + talk(editor, from: 150, for: 150)
        let a = ChapterDetector.detect(segments: lines, duration: 300)
        let b = ChapterDetector.detect(segments: lines.reversed(), duration: 300)
        #expect(a.map(\.start) == b.map(\.start))
        #expect(a.map(\.title) == b.map(\.title))
    }

    @Test func aChapterBeginsJustBeforeItsFirstLineNotInsideTheLineBefore() {
        let lines = talk(billing, from: 0, for: 150) + talk(editor, from: 150, for: 150)
        let chapters = ChapterDetector.detect(segments: lines, duration: 300)
        let first = lines.first { $0.start >= chapters[1].start }!
        let previous = lines.last { $0.end <= first.start }!
        #expect(chapters[1].start <= first.start)
        #expect(chapters[1].start >= previous.end)
    }

    // MARK: Titles

    @Test func fallbackTitlesUseASectionsOwnDistinctiveWords() {
        let lines = talk(billing, from: 0, for: 150) + talk(editor, from: 150, for: 150)
        let chapters = ChapterDetector.detect(segments: lines, duration: 300)
        let first = chapters[0].title.lowercased(), second = chapters[1].title.lowercased()
        #expect(billing.contains { first.contains($0) })
        #expect(editor.contains { second.contains($0) })
        #expect(!editor.contains { first.contains($0) })
    }

    @Test func sectionsSplitLinesByChapterStart() {
        let lines = talk(billing, from: 0, for: 20) + talk(editor, from: 20, for: 20)
        let sections = ChapterDetector.sections(of: lines, chapters: [Chapter(start: 0, title: "A"), Chapter(start: 20, title: "B")])
        #expect(sections.map(\.count) == [4, 4])
        #expect(sections[1].allSatisfy { $0.start >= 20 })
    }

    @Test func signpostsAreFoundAfterFillerButNotInTheMiddleOfASentence() {
        #expect(ChapterDetector.opensNewPart("Okay, so let's look at the invoices"))
        #expect(ChapterDetector.opensNewPart("Moving on to exports."))
        #expect(ChapterDetector.opensNewPart("And finally, a word on pricing"))
        #expect(!ChapterDetector.opensNewPart("The invoice goes next to the receipt"))
        #expect(!ChapterDetector.opensNewPart("So that is how it works"))
    }

    // MARK: The model's reply

    @Test func aTitleReplyIsCleaned() {
        #expect(ChapterPrompt.parse("\"Setting up billing.\"") == "Setting up billing")
        #expect(ChapterPrompt.parse("Title: Exporting a video") == "Exporting a video")
        #expect(ChapterPrompt.parse("Chapter 2: Trimming clips\nA longer note") == "Trimming clips")
        #expect(ChapterPrompt.parse("- Hiring panel") == "Hiring panel")
    }

    @Test func aReplyThatIsNotATitleIsRefused() {
        #expect(ChapterPrompt.parse("") == nil)
        #expect(ChapterPrompt.parse("  \n ") == nil)
        #expect(ChapterPrompt.parse("In this section the speaker walks through how invoices are created and then sent out to customers") == nil)
    }

    @Test func aLongSectionIsClippedForTheModelKeepingBothEnds() {
        let long = [CaptionSegment(start: 0, end: 1, text: "START " + String(repeating: "word ", count: 2000) + "END")]
        let prompt = ChapterPrompt.prompt(for: long, number: 2, of: 5)
        #expect(prompt.contains("START") && prompt.contains("END"))
        #expect(prompt.count < ChapterPrompt.maxCharacters + 200)
        #expect(prompt.contains("Section 2 of 5"))
    }

    // MARK: The list

    @Test func aTidyListIsSortedInRangeAndNamed() {
        let tidy = ChapterList.normalized([
            Chapter(start: 120, title: "  Later   part "), Chapter(start: -5, title: ""), Chapter(start: 120.4, title: "Duplicate"),
            Chapter(start: 999, title: "After the end"), Chapter(start: .nan, title: "Broken"),
        ], duration: 300)
        #expect(tidy.map(\.start) == [0, 120])
        #expect(tidy.map(\.title) == ["Chapter 1", "Later part"])
    }

    @Test func theChapterBeingPlayedIsTheLastOneStarted() {
        let list = [Chapter(start: 0, title: "A"), Chapter(start: 60, title: "B"), Chapter(start: 120, title: "C")]
        #expect(ChapterList.activeIndex(in: list, at: 0) == 0)
        #expect(ChapterList.activeIndex(in: list, at: 59.99) == 1)  // within the half-tick of the player's clock
        #expect(ChapterList.activeIndex(in: list, at: 100) == 1)
        #expect(ChapterList.activeIndex(in: list, at: 500) == 2)
        #expect(ChapterList.activeIndex(in: [Chapter(start: 10, title: "X")], at: 3) == nil)
    }

    @Test func timestampsReadLikeAVideoDescription() {
        let list = [Chapter(start: 0, title: "Intro"), Chapter(start: 65.9, title: "Billing"), Chapter(start: 3725, title: "Wrap up")]
        #expect(ChapterList.timestampList(list) == "0:00 Intro\n1:05 Billing\n1:02:05 Wrap up")
    }

    // MARK: Saving

    @Test func chaptersSurviveTheSidecarAndOldSidecarsHaveNone() throws {
        let chapters = [Chapter(start: 0, title: "Intro"), Chapter(start: 42, title: "Billing")]
        var metadata = TakeMetadata(title: "T", summary: "", created: Date(timeIntervalSince1970: 0))
        metadata.chapters = chapters
        let back = try TakeMetadata.decode(try metadata.encoded())
        #expect(back.chapters == chapters)

        let old = #"{"title":"T","summary":"","created":"1970-01-01T00:00:00Z"}"#
        #expect(try TakeMetadata.decode(Data(old.utf8)).chapters.isEmpty)
        // A chapter written by hand with no id or title still opens.
        let bare = #"{"title":"T","summary":"","created":"1970-01-01T00:00:00Z","chapters":[{"start":5}]}"#
        let decoded = try TakeMetadata.decode(Data(bare.utf8)).chapters
        #expect(decoded.count == 1 && decoded[0].start == 5 && decoded[0].title.isEmpty)
    }

    @Test func turningChaptersOffForATakeSurvivesTheSidecarAndKeepsThem() throws {
        var metadata = TakeMetadata(title: "T", summary: "", created: Date(timeIntervalSince1970: 0))
        #expect(metadata.chaptersEnabled == nil)  // follows the app-wide default
        metadata.chapters = [Chapter(start: 0, title: "Intro")]
        metadata.chaptersEnabled = false
        let back = try TakeMetadata.decode(try metadata.encoded())
        #expect(back.chaptersEnabled == false && back.chapters.count == 1)

        let old = #"{"title":"T","summary":"","created":"1970-01-01T00:00:00Z"}"#
        #expect(try TakeMetadata.decode(Data(old.utf8)).chaptersEnabled == nil)
    }

    @Test func savingChaptersKeepsTheRestOfTheNotes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("chapters-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = TakeFiles(directory: directory, baseName: "Take")
        let entry = TakeEntry(files: files, folder: "", created: Date(), title: "T", summary: "S", tags: ["a"], hasCaptions: false)
        try TakeMetadata(title: "T", summary: "S", created: Date(), durationSeconds: 100, tags: ["a"], notes: "N").encoded().write(to: files.metadata)

        let saved = try TakeLibrary.saveChapters(
            [Chapter(start: 50, title: "B"), Chapter(start: 0, title: "A"), Chapter(start: 400, title: "Past the end")], for: entry)
        #expect(saved.map(\.title) == ["A", "B"])
        let metadata = try #require(TakeLibrary.metadata(for: files))
        #expect(metadata.chapters == saved)
        #expect(metadata.notes == "N" && metadata.tags == ["a"] && metadata.summary == "S")
    }

    @Test func aCopyCarriesTheOriginalsChoiceToHideChapters() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("chapters-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = TakeFiles(directory: directory, baseName: "Copy")
        try TakeLibrary.saveChapters([Chapter(start: 0, title: "A")], to: files, created: Date(), duration: 60, chaptersEnabled: false)
        #expect(TakeLibrary.metadata(for: files)?.chaptersEnabled == false)
        // Passing nothing leaves the choice that is there.
        try TakeLibrary.saveChapters([Chapter(start: 0, title: "A")], to: files, created: Date(), duration: 60)
        #expect(TakeLibrary.metadata(for: files)?.chaptersEnabled == false)
    }

    // MARK: Through cuts

    private let threeParts = [Chapter(start: 0, title: "A"), Chapter(start: 100, title: "B"), Chapter(start: 200, title: "C")]

    private func cut(_ ranges: [(Double, Double)], of duration: Double = 300) throws -> EditModel {
        var model = EditModel(duration: duration)
        for range in ranges { try model.remove(TimeSpan(start: range.0, end: range.1)) }
        return model
    }

    @Test func chaptersAreUnchangedWhenNothingIsCut() throws {
        let moved = ChapterList.remapped(threeParts, through: EditModel(duration: 300))
        #expect(moved == threeParts)
    }

    @Test func aCutInsideAChapterMovesTheLaterChaptersEarlier() throws {
        let moved = ChapterList.remapped(threeParts, through: try cut([(40, 70)]))
        #expect(moved.map(\.start) == [0, 70, 170])
        #expect(moved.map(\.title) == ["A", "B", "C"])
        #expect(moved.map(\.id) == threeParts.map(\.id))
    }

    @Test func aChapterWhoseOpeningWasCutStartsWhereItsRemainingFootageDoes() throws {
        // Source 90–130 is gone, so B (from 100) now begins with what was at 130, which plays at 90.
        let moved = ChapterList.remapped(threeParts, through: try cut([(90, 130)]))
        #expect(moved.map(\.start) == [0, 90, 160])
    }

    @Test func aChapterThatWasCutEntirelyIsDropped() throws {
        let moved = ChapterList.remapped(threeParts, through: try cut([(100, 200)]))
        #expect(moved.map(\.title) == ["A", "C"])
        #expect(moved.map(\.start) == [0, 100])
    }

    @Test func aChapterLeftWithAFewMomentsIsDropped() throws {
        // Only source 100–100.5 of B survives: too little to be a chapter.
        let moved = ChapterList.remapped(threeParts, through: try cut([(100.5, 200)]))
        #expect(moved.map(\.title) == ["A", "C"])
    }

    @Test func cuttingTheStartOfTheRecordingLeavesTheFirstSurvivingChapterAtZero() throws {
        let moved = ChapterList.remapped(threeParts, through: try cut([(0, 100)]))
        #expect(moved.map(\.title) == ["B", "C"])
        #expect(moved.map(\.start) == [0, 100])
    }

    @Test func severalCutsAddUp() throws {
        let moved = ChapterList.remapped(threeParts, through: try cut([(10, 20), (150, 160), (250, 260)]))
        #expect(moved.map(\.start) == [0, 90, 180])
    }

    @Test func aCopyGetsItsChaptersWithoutLosingItsNotes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("chapters-copy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = TakeFiles(directory: directory, baseName: "Copy")

        // With no notes yet, they are made.
        try TakeLibrary.saveChapters([Chapter(start: 0, title: "A"), Chapter(start: 70, title: "B")], to: files, created: Date(), duration: 270)
        #expect(TakeLibrary.metadata(for: files)?.chapters.map(\.title) == ["A", "B"])

        // With notes already written (by the pipeline), they are kept.
        try TakeMetadata(title: "T", summary: "S", created: Date(), durationSeconds: 270, notes: "N").encoded().write(to: files.metadata)
        try TakeLibrary.saveChapters([Chapter(start: 0, title: "A"), Chapter(start: 999, title: "Past the end")], to: files, created: Date(), duration: nil)
        let metadata = try #require(TakeLibrary.metadata(for: files))
        #expect(metadata.chapters.map(\.title) == ["A"])
        #expect(metadata.title == "T" && metadata.notes == "N")
    }
}
