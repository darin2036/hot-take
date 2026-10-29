import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct BugReportTests {
    private func line(_ start: Double, _ end: Double, _ text: String) -> CaptionSegment {
        CaptionSegment(start: start, end: end, text: text)
    }

    private let draft = BugReport.Draft(
        title: "Save does nothing", summary: "Clicking Save on a new draft does not save it.",
        steps: [
            BugReport.Step(text: "Open a new draft", picture: 1), BugReport.Step(text: "Click Save", picture: 2),
            BugReport.Step(text: "  ", picture: 3),
        ],
        expected: "A toast appears.", actual: "Nothing happens.", environment: "Safari 19")
    private let names = ["01-0m01s.png", "02-0m03s.png", "03-0m05s.png"]

    @Test func markdownIsATicketBodyWithoutTheTitle() {
        let text = BugReport.text(of: draft, format: .markdown, pictures: names)
        #expect(text == """
            Clicking Save on a new draft does not save it.

            ## Steps to reproduce
            1. Open a new draft (01-0m01s.png)
            2. Click Save (02-0m03s.png)

            ## Expected
            A toast appears.

            ## Actual
            Nothing happens.

            ## Environment
            Safari 19

            """)
    }

    @Test func eachPlaceWritesItsOwnMarkup() {
        let jira = BugReport.text(of: draft, format: .jira, pictures: names)
        #expect(jira.contains("h3. Steps to reproduce\n# Open a new draft (01-0m01s.png)\n# Click Save (02-0m03s.png)"))
        #expect(jira.contains("h3. Expected\nA toast appears."))
        #expect(!jira.contains("Save does nothing\n"))

        // Slack has no title field, so the title leads the message in bold.
        let slack = BugReport.text(of: draft, format: .slack, pictures: names)
        #expect(slack.hasPrefix("*Save does nothing*\n\nClicking Save"))
        #expect(slack.contains("*Steps to reproduce*\n1. Open a new draft"))

        let plain = BugReport.text(of: draft, format: .plain, pictures: names)
        #expect(plain.contains("Steps to reproduce:\n1. Open"))
        #expect(!plain.contains("#") && !plain.contains("*"))

        let saved = BugReport.text(of: draft, format: .markdown, pictures: names, includeTitle: true)
        #expect(saved.hasPrefix("# Save does nothing\n\n"))
    }

    @Test func emptyPartsAndUnusedStepsAreLeftOut() {
        let text = BugReport.text(
            of: BugReport.Draft(summary: "Crash.", steps: [BugReport.Step(text: "", picture: 1)], actual: "It quits."),
            format: .markdown, pictures: names)
        #expect(text == "Crash.\n\n## Actual\nIt quits.\n")
        // A step whose picture is missing still reads fine.
        let step = BugReport.Draft(steps: [BugReport.Step(text: "Click it", picture: 9), BugReport.Step(text: "Then wait")])
        #expect(BugReport.text(of: step, format: .markdown, pictures: names) == "## Steps to reproduce\n1. Click it\n2. Then wait\n")
    }

    @Test func theDraftHasARowForEachPictureAndFallsBackToWhatWasSaid() {
        let moments = [AgentBrief.Moment(time: 2, click: ClickEvent(time: 2, x: 0.4, y: 0.2)), AgentBrief.Moment(time: 12)]
        let metadata = TakeMetadata(
            title: "Take title", summary: "", created: Date(),
            transcript: [line(1, 3, "I open the draft. Then more."), line(11, 13, "Nothing happens.")])
        let plain = BugReport.draft(metadata: metadata, moments: moments, steps: [:], reading: nil)
        #expect(plain.title == "Take title")
        #expect(plain.steps.map(\.text) == ["I open the draft", "Nothing happens"])
        #expect(plain.steps.map(\.picture) == [1, 2])

        let model = BugReport.draft(
            metadata: metadata, moments: moments, steps: [1: "Open the draft"],
            reading: BugReport.Reading(title: "Draft will not save", summary: "Save fails.", expected: "A toast", actual: ""))
        #expect(model.title == "Draft will not save")
        #expect(model.steps.map(\.text) == ["Open the draft", ""])
        #expect(model.summary == "Save fails." && model.expected == "A toast" && model.actual == "")
    }

    @Test func theModelsReplyIsReadInAnyCommonShape() {
        let reply = """
            Here you go.
            TITLE: "Save button does nothing"
            SUMMARY: Save fails
            on a new draft.
            EXPECTED: A toast appears.
            ACTUAL: Not stated
            """
        let reading = BugReportPrompt.parse(reply)
        #expect(reading?.title == "Save button does nothing")
        #expect(reading?.summary == "Save fails on a new draft.")
        #expect(reading?.expected == "A toast appears.")
        #expect(reading?.actual == "")
        #expect(BugReportPrompt.parse("I can't help with that.") == nil)
        #expect(BugReportPrompt.parse("TITLE: Not stated\nSUMMARY: None\nEXPECTED: n/a\nACTUAL: Not stated") == nil)
    }

    @Test func stepsAreReadByMomentNumber() {
        let reply = """
            1: Open the Orders page
            2. SKIP
            3) "Click Save"
            garbage
            4:
            1: A second answer for one
            """
        #expect(BugReportPrompt.parseSteps(reply) == [1: "Open the Orders page", 3: "Click Save"])
        #expect(BugReportPrompt.stepLine(number: 2, clicked: true, narration: "  hi ") == "2 (clicked): hi")
        #expect(BugReportPrompt.stepLine(number: 3, clicked: false, narration: "") == "3 (talking): (nothing said)")
    }

    @Test func momentsAreSentToTheModelInBatchesThatFit() {
        let lines = (1...10).map { BugReportPrompt.stepLine(number: $0, clicked: true, narration: String(repeating: "a", count: 40)) }
        let batches = BugReportPrompt.stepBatches(lines, maxCharacters: 200)
        #expect(batches.flatMap { Array($0) } == Array(0..<10))
        #expect(batches.count > 1)
        #expect(batches.allSatisfy { lines[$0].reduce(0) { $0 + $1.count + 1 } <= 200 })
        #expect(BugReportPrompt.stepBatches([], maxCharacters: 200).isEmpty)
    }

    @Test func readingsFromLongRecordingsCombine() {
        let a = BugReport.Reading(title: "", summary: "", expected: "", actual: "")
        let b = BugReport.Reading(title: "Save fails", summary: "It fails.", expected: "A toast", actual: "Nothing")
        #expect(BugReportPrompt.combined([a, b]) == b)
        #expect(BugReportPrompt.combined([]) == nil)
        #expect(BugReportPrompt.mergeText([a, b]).contains("Part 2 of the recording. Title: Save fails"))
    }

    @Test func writingSavesAnEditableDraftBesideTheTakeAndItMovesWithIt() async throws {
        let video = try await TestMedia.video(seconds: 4, color: (40, 120, 200))
        let directory = video.deletingLastPathComponent().appendingPathComponent("bug-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = TakeFiles(directory: directory, baseName: "Take")
        try FileManager.default.moveItem(at: video, to: files.video)
        var metadata = TakeMetadata(title: "Broken list", summary: "", created: Date(), transcript: [line(0.5, 1.5, "This list is empty.")])
        metadata.clicks = [ClickEvent(time: 3, x: 0.5, y: 0.5)]

        #expect(BugReport.load(for: files) == nil)
        let plan = try await AgentBrief.plan(for: files, metadata: metadata)
        let first = BugReport.draft(metadata: metadata, moments: plan.moments, steps: [:], reading: nil)
        let saved = try await BugReport.write(for: files, plan: plan, draft: first)
        #expect(saved.folder == files.bugReportDirectory)
        #expect(saved.pictureNames == ["01-0m01s.png", "02-0m03s.png"])
        #expect(saved.pictures.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let markdown = try String(contentsOf: saved.markdownFile, encoding: .utf8)
        #expect(markdown.hasPrefix("# Broken list\n"))
        #expect(markdown.contains("1. This list is empty (01-0m01s.png)"))
        // The agent request is a separate folder and is not touched.
        #expect(!FileManager.default.fileExists(atPath: files.agentDirectory.path))

        // Edits are saved over it, and reopen as they were left.
        var edited = saved
        edited.draft.title = "List is empty after login"
        edited.draft.steps.removeLast()
        try BugReport.save(edited)
        let reopened = try #require(BugReport.load(for: files))
        #expect(reopened.draft.title == "List is empty after login")
        #expect(reopened.draft.steps.map(\.text) == ["This list is empty"])
        #expect(reopened.draft.steps.map(\.picture) == [1])

        // A draft whose pictures are gone is not reopened.
        try FileManager.default.removeItem(at: saved.pictures[0])
        #expect(BugReport.load(for: files) == nil)
        let again = try await BugReport.write(for: files, plan: plan, draft: first)
        #expect(again.pictures.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        // It goes with the take.
        let library = directory.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let entry = try #require(TakeLibrary.load(directory: directory).first { $0.files.baseName == "Take" })
        let moved = try TakeLibrary.move(entry, toFolder: "Folder", root: directory)
        #expect(BugReport.load(for: moved) != nil)
        #expect(!FileManager.default.fileExists(atPath: files.bugReportDirectory.path))
    }
}
