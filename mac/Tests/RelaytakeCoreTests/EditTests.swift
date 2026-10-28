import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct EditModelTests {
    @Test func removesMiddleAndJoins() throws {
        var model = EditModel(duration: 10)
        try model.remove(TimeSpan(start: 3, end: 6))
        #expect(model.segments == [TimeSpan(start: 0, end: 3), TimeSpan(start: 6, end: 10)])
        #expect(model.keptDuration == 7)
        #expect(model.isEdited)
    }

    @Test func rejectsInvalidAndEmptyEdits() {
        for range in [(0.0, 10.0), (2, 1), (.nan, 4), (-1, 3)] {
            var model = EditModel(duration: 10)
            #expect(throws: EditError.self) { try model.remove(TimeSpan(start: range.0, end: range.1)) }
            #expect(model.segments == [TimeSpan(start: 0, end: 10)])
        }
    }

    @Test func mapsSourceTimeToOutputTime() throws {
        var model = EditModel(duration: 10)
        try model.remove(TimeSpan(start: 3, end: 6))
        #expect(model.outputTime(forSource: 2) == 2)
        #expect(model.outputTime(forSource: 4) == nil)
        #expect(model.outputTime(forSource: 7) == 4)
    }
}

@Suite struct LibraryTests {
    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("relaytake-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func listsTakesNewestFirstWithSidecars() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["a", "b"] { try Data().write(to: folder.appendingPathComponent("\(name).mp4")) }
        let metadata = TakeMetadata(title: "Titled", summary: "S", created: Date(timeIntervalSince1970: 2_000_000_000))
        try metadata.encoded().write(to: folder.appendingPathComponent("b.json"))
        try Data().write(to: folder.appendingPathComponent("b.vtt"))
        try Data().write(to: folder.appendingPathComponent("notes.txt"))

        let takes = TakeLibrary.load(directory: folder)
        #expect(takes.map(\.files.baseName) == ["b", "a"])
        #expect(takes[0].title == "Titled" && takes[0].hasCaptions)
        #expect(takes[1].title == TakeEntry.untitled && !takes[1].hasCaptions)
    }

    @Test func renameWritesSidecarAndKeepsVideoName() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("a.mp4"))
        let entry = TakeLibrary.load(directory: folder)[0]
        try TakeLibrary.rename(entry, to: "  New name  ")
        #expect(TakeLibrary.load(directory: folder)[0].title == "New name")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.mp4").path))
    }

    @Test func copyNamesNeverCollide() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(TakeLibrary.uniqueCopyName(basedOn: "Demo", in: folder) == "Demo (edited)")
        try Data().write(to: folder.appendingPathComponent("Demo (edited).mp4"))
        #expect(TakeLibrary.uniqueCopyName(basedOn: "Demo", in: folder) == "Demo (edited 2)")
    }
}

@Suite struct GeometryTests {
    @Test func flipsBottomLeftRectToTopLeft() {
        // 100×50 box whose bottom edge is 20pt above the bottom of a 1000pt-tall display.
        let flipped = CaptureGeometry.topLeftRect(
            fromBottomLeft: CGRect(x: 40, y: 20, width: 100, height: 50), displayHeight: 1000)
        #expect(flipped == CGRect(x: 40, y: 930, width: 100, height: 50))
        // A box hugging the top of the display lands at y = 0.
        let top = CaptureGeometry.topLeftRect(
            fromBottomLeft: CGRect(x: 0, y: 900, width: 10, height: 100), displayHeight: 1000)
        #expect(top.minY == 0)
    }

    @Test func roundsPixelSizesDownToEven() {
        let size = CaptureGeometry.evenPixelSize(points: CGSize(width: 501, height: 333), scale: 2)
        #expect(size.width == 1002 && size.height == 666)
        let odd = CaptureGeometry.evenPixelSize(points: CGSize(width: 100.7, height: 41), scale: 1)
        #expect(odd.width == 100 && odd.height == 40)
        #expect(CaptureGeometry.evenPixelSize(points: .zero, scale: 2).width == 2)
    }
}

@Suite struct FolderTests {
    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("relaytake-\(UUID().uuidString)").standardizedFileURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    @Test func scansSubfoldersWithUniqueIDsAndSkipsHidden() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root.appendingPathComponent("a.mp4"))
        try touch(root.appendingPathComponent("Demos/a.mp4"))  // same name, different folder
        try touch(root.appendingPathComponent("Demos/Q4/b.mp4"))
        try touch(root.appendingPathComponent(".relaytake-processing/hidden.mp4"))

        let takes = TakeLibrary.load(directory: root)
        #expect(Set(takes.map(\.id)) == ["a", "Demos/a", "Demos/Q4/b"])
        #expect(takes.first { $0.id == "Demos/Q4/b" }?.folder == "Demos/Q4")
        #expect(takes.first { $0.id == "a" }?.folder == "")
    }

    @Test func buildsFolderTreeWithoutHiddenFolders() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["Demos/Q4", "Bugs", ".relaytake-processing"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        let tree = TakeLibrary.folders(in: root)
        #expect(tree.map(\.name) == ["Bugs", "Demos"])
        #expect(tree[1].children.map(\.path) == ["Demos/Q4"])
        #expect(tree[0].childrenOrNil == nil)
    }

    @Test func createsRenamesAndRejectsBadFolderNames() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try TakeLibrary.createFolder(named: " Demos ", in: "", root: root)
        let second = try TakeLibrary.createFolder(named: "Demos", in: "", root: root)
        let child = try TakeLibrary.createFolder(named: "a/b:c", in: first, root: root)
        #expect(first == "Demos" && second == "Demos 2" && child == "Demos/a-b-c")
        #expect(throws: LibraryError.invalidName) { try TakeLibrary.createFolder(named: "  ", in: "", root: root) }
        #expect(throws: LibraryError.invalidName) { try TakeLibrary.createFolder(named: "...", in: "", root: root) }
        #expect(throws: LibraryError.outsideLibrary) { try TakeLibrary.createFolder(named: "x", in: "../..", root: root) }

        let renamed = try TakeLibrary.renameFolder("Demos/a-b-c", to: "Q4", root: root)
        #expect(renamed == "Demos/Q4")
        #expect(throws: LibraryError.invalidName) { try TakeLibrary.renameFolder("Demos", to: "Demos 2", root: root) }
    }

    @Test func movesTakeFilesTogetherAndAvoidsClashes() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for ext in ["mp4", "vtt", "json"] { try touch(root.appendingPathComponent("a.\(ext)")) }
        try touch(root.appendingPathComponent("Demos/a.mp4"))  // clash at the destination

        let entry = TakeLibrary.load(directory: root).first { $0.id == "a" }!
        let moved = try TakeLibrary.move(entry, toFolder: "Demos", root: root)

        #expect(moved.baseName == "a 2")
        for ext in ["mp4", "vtt", "json"] {
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Demos/a 2.\(ext)").path))
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("a.\(ext)").path))
        }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Demos/a.mp4").path))
        // Moving to where it already is changes nothing.
        let again = TakeLibrary.load(directory: root).first { $0.id == "Demos/a 2" }!
        #expect(try TakeLibrary.move(again, toFolder: "Demos", root: root) == again.files)
    }
}

@Suite struct MetadataEditingTests {
    @Test func parsesTagsTrimmedAndDeduplicated() {
        #expect(TakeMetadata.parseTags("demo, Bug Report ,, DEMO\nlaunch") == ["demo", "Bug Report", "launch"])
        #expect(TakeMetadata.parseTags("  ").isEmpty)
    }

    @Test func oldSidecarsWithoutTagsStillDecode() throws {
        let json = #"{"title":"T","summary":"S","created":"2026-10-21T16:31:17Z","transcript":[]}"#
        let metadata = try TakeMetadata.decode(Data(json.utf8))
        #expect(metadata.tags.isEmpty && metadata.notes.isEmpty && metadata.title == "T")
    }

    @Test func updateKeepsOtherFieldsAndSearchFindsTags() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("relaytake-\(UUID().uuidString)").standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("a.mp4"))
        let original = TakeMetadata(title: "Old", summary: "Keep me", created: Date(timeIntervalSince1970: 1_700_000_000),
                                    transcript: [.init(start: 0, end: 1, text: "Hi")])
        try original.encoded().write(to: root.appendingPathComponent("a.json"))

        let entry = TakeLibrary.load(directory: root)[0]
        try TakeLibrary.update(entry) { $0.tags = ["launch"]; $0.notes = "Send to Sam" }

        let saved = TakeLibrary.metadata(for: entry.files)!
        #expect(saved.title == "Old" && saved.summary == "Keep me" && saved.transcript.count == 1)
        #expect(saved.tags == ["launch"] && saved.notes == "Send to Sam")
        let reloaded = TakeLibrary.load(directory: root)[0]
        #expect(reloaded.matches("LAUNCH") && reloaded.matches("keep") && !reloaded.matches("zzz"))
        #expect(reloaded.matches("  "))
    }
}

@Suite struct SelectionTests {
    private let order = ["a", "b", "c", "d", "e"]

    @Test func plainCommandAndShiftClicks() {
        var s = SelectionState()
        s.click("b", order: order, command: false, shift: false)
        #expect(s.selected == ["b"])
        s.click("d", order: order, command: true, shift: false)
        #expect(s.selected == ["b", "d"])
        s.click("b", order: order, command: true, shift: false)  // toggles off
        #expect(s.selected == ["d"])
        // The anchor is the last item clicked (b), so ⇧-click on a selects a…b.
        s.click("a", order: order, command: false, shift: true)
        #expect(s.selected == ["a", "b"])
        s.click("e", order: order, command: true, shift: true)  // b…e added to what is selected
        #expect(s.selected == ["a", "b", "c", "d", "e"])
        s.click("c", order: order, command: false, shift: false)
        #expect(s.selected == ["c"] && s.anchor == "c")
    }

    @Test func shiftWithoutAnchorActsLikePlainClick() {
        var s = SelectionState()
        s.click("c", order: order, command: false, shift: true)
        #expect(s.selected == ["c"])
    }

    @Test func selectAllClearAndOrdering() {
        var s = SelectionState()
        s.selectAll(order)
        #expect(s.count == 5)
        s.set(["d", "b"])
        #expect(s.ordered(by: order) == ["b", "d"])
        s.clear()
        #expect(s.isEmpty && s.anchor == nil && s.cursor == nil)
    }

    @Test func arrowKeysMoveAndExtend() {
        var s = SelectionState()
        s.move(by: 1, order: order, extend: false)  // nothing selected: start at the first
        #expect(s.selected == ["a"])
        s.move(by: 2, order: order, extend: false)
        #expect(s.selected == ["c"])
        s.move(by: 1, order: order, extend: true)
        #expect(s.selected == ["c", "d"])
        s.move(by: 1, order: order, extend: true)
        #expect(s.selected == ["c", "d", "e"])
        s.move(by: 5, order: order, extend: false)  // clamps at the end
        #expect(s.selected == ["e"])
        var empty = SelectionState()
        empty.move(by: -1, order: order, extend: false)  // up with nothing selected: start at the last
        #expect(empty.selected == ["e"])
    }

    @Test func boxSelectionReplacesOrAddsAndPruneDropsMissing() {
        var s = SelectionState()
        s.click("a", order: order, command: false, shift: false)
        s.box(hits: ["c", "d"], base: ["a"], additive: false, order: order)
        #expect(s.selected == ["c", "d"])
        s.box(hits: ["e"], base: ["c", "d"], additive: true, order: order)
        #expect(s.selected == ["c", "d", "e"])
        s.prune(keeping: ["c", "x"])
        #expect(s.selected == ["c"])
    }
}

@Suite struct MetadataPromptTests {
    @Test func cleansTitlesAndSummaries() {
        #expect(MetadataPrompt.clean("Title: \"Checkout bug walkthrough.\"\nExtra line", for: .title) == "Checkout bug walkthrough")
        #expect(MetadataPrompt.clean("Summary: “The cart total is wrong.”", for: .summary) == "The cart total is wrong.")
    }

    @Test func cleansTags() {
        #expect(MetadataPrompt.clean("Tags: #Checkout, bug report, - Rounding, checkout, \"cart\".", for: .tags)
            == "checkout, bug report, rounding, cart")
        let many = (1...10).map { "t\($0)" }.joined(separator: ", ")
        #expect(MetadataPrompt.clean(many, for: .tags).split(separator: ",").count == 6)
    }

    @Test func cleansNotes() {
        #expect(MetadataPrompt.clean("None", for: .notes) == "")
        #expect(MetadataPrompt.clean("none.", for: .notes) == "")
        #expect(MetadataPrompt.clean("* Fix rounding\n• Send to Sam\n\n- Review PR", for: .notes)
            == "- Fix rounding\n- Send to Sam\n- Review PR")
    }

    @Test func promptsNameTheFieldAndCarryTheTranscript() {
        for field in MetadataField.allCases {
            let prompt = MetadataPrompt.prompt(for: field, transcript: "hello world")
            #expect(prompt.hasPrefix(MetadataPrompt.request(field)) && prompt.hasSuffix("hello world"))
        }
    }
}

@Suite struct EditSuggestionTests {
    @Test func findsQuietRunsLongEnough() {
        // 0.5 s windows: loud, then 4 quiet windows (2 s), loud, then 1 quiet window (0.5 s), loud.
        let levels: [Double] = [-20, -60, -60, -60, -60, -20, -60, -20]
        let spans = SilenceDetector.quietSpans(levels: levels, windowSeconds: 0.5, thresholdDB: -45, minDuration: 1.5)
        #expect(spans == [TimeSpan(start: 0.5, end: 2.5)])
        // A run that reaches the end of the recording still counts.
        let tail = SilenceDetector.quietSpans(levels: [-20, -60, -60, -60, -60], windowSeconds: 0.5, thresholdDB: -45, minDuration: 1.5)
        #expect(tail == [TimeSpan(start: 0.5, end: 2.5)])
        #expect(SilenceDetector.quietSpans(levels: levels, windowSeconds: 0, thresholdDB: -45, minDuration: 1).isEmpty)
    }

    @Test func thresholdAdaptsToTheNoiseFloorWithinLimits() {
        #expect(SilenceDetector.threshold(levels: []) == -45)
        #expect(SilenceDetector.threshold(levels: Array(repeating: -90, count: 20)) == -60)  // clamped low
        #expect(SilenceDetector.threshold(levels: Array(repeating: -10, count: 20)) == -35)  // clamped high
        let mixed = Array(repeating: -50.0, count: 10) + Array(repeating: -15.0, count: 90)
        #expect(SilenceDetector.threshold(levels: mixed) == -42)  // floor -50 + 8
    }

    @Test func trimsPaddingAndDropsShortSpans() {
        let spans = [TimeSpan(start: 10, end: 14), TimeSpan(start: 20, end: 21)]
        #expect(SilenceDetector.trimmed(spans, by: 0.25, minLength: 1) == [TimeSpan(start: 10.25, end: 13.75)])
    }

    @Test func findsPausesBetweenSpokenSegments() {
        let segments = [
            CaptionSegment(start: 2, end: 4, text: "a"), CaptionSegment(start: 4.2, end: 5, text: "b"),
            CaptionSegment(start: 9, end: 10, text: "c"),
        ]
        let gaps = TranscriptGaps.gaps(segments: segments, duration: 14, minGap: 2)
        #expect(gaps == [TimeSpan(start: 0, end: 2), TimeSpan(start: 5, end: 9), TimeSpan(start: 10, end: 14)])
    }

    @Test func numbersSegmentsAndRespectsTheBudget() {
        let segments = (1...5).map { CaptionSegment(start: Double($0), end: Double($0) + 1, text: "line \($0)") }
        let all = EditPrompt.numbered(segments)
        #expect(all.included == 5 && all.text.hasPrefix("[1] line 1\n"))
        let small = EditPrompt.numbered(segments, maxCharacters: 25)
        #expect(small.included == 2)
    }

    @Test func parsesCutsAndDropsInvalidOnes() {
        let segments = (1...6).map { CaptionSegment(start: Double($0) * 10, end: Double($0) * 10 + 8, text: "s\($0)") }
        let reply = """
        CUT 2-3: false start, repeated
        - CUT [5]: filler only
        CUT 4-9: out of range
        CUT 3-2: reversed
        Here is my analysis
        CUT x-y: nonsense
        CUT 1-1:
        """
        let cuts = EditPrompt.parse(reply, segments: segments)
        #expect(cuts.map(\.span) == [TimeSpan(start: 20, end: 38), TimeSpan(start: 50, end: 58), TimeSpan(start: 10, end: 18)])
        #expect(cuts[0].reason == "false start, repeated" && cuts[2].reason == "Suggested cut")
        #expect(cuts.allSatisfy { $0.kind == .recommended })
        #expect(EditPrompt.parse("NONE", segments: segments).isEmpty)
        #expect(EditPrompt.parse(String(repeating: "CUT 1-1: a\n", count: 9), segments: segments).count == 5)
    }

    @Test func combinesSilenceAndRecommendationsInTimeOrder() {
        let recommended = [EditSuggestion(kind: .recommended, span: TimeSpan(start: 30, end: 40), reason: "tangent")]
        let combined = EditSuggestions.combine(
            audioSilences: [TimeSpan(start: 5, end: 8), TimeSpan(start: 32, end: 35)],
            transcriptGaps: [TimeSpan(start: 7, end: 9)],
            recommended: recommended)
        #expect(combined.map(\.span) == [TimeSpan(start: 5, end: 9), TimeSpan(start: 30, end: 40)])
        #expect(combined.map(\.kind) == [.silence, .recommended])  // the silence inside the cut is redundant
    }
}
