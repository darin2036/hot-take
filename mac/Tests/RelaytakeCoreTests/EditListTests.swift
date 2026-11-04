import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct EditListTests {
    private let markers = [
        AgentMarker(name: "Intro", time: 0),
        AgentMarker(name: "Loading", time: 10),
        AgentMarker(name: "Loaded", time: 20),
        AgentMarker(name: "Studio", time: 25),
    ]

    private func apply(_ list: EditList, duration: Double = 40, clicks: [ClickEvent] = []) -> (StudioProject, EditListOutcome) {
        EditListApplier.apply(list, to: StudioProject(duration: duration), markers: markers, clicks: clicks)
    }

    @Test func timeRefsReadNumbersMarkersAndOffsets() throws {
        let decoded = try JSONDecoder().decode([TimeRef].self, from: Data("[3.5, \"Loading\", \"loaded+1.5\", \"Studio-2\"]".utf8))
        #expect(decoded.map { $0.resolve(markers: markers) } == [3.5, 10, 21.5, 23])
        #expect(TimeRef.marker("Nope").resolve(markers: markers) == nil)
        #expect(TimeRef.seconds(.nan).resolve(markers: markers) == nil)
    }

    @Test func cuttingBetweenMarkersRemovesTheWaitAndKeepsTheRest() {
        let (project, outcome) = apply(EditList(cuts: [.init(from: .marker("Loading"), to: .marker("Loaded"))]))
        #expect(project.outputDuration == 30)
        #expect(project.cuts.segments == [TimeSpan(start: 0, end: 10), TimeSpan(start: 20, end: 40)])
        #expect(outcome.warnings.isEmpty)
        #expect(outcome.applied.first?.hasPrefix("Cut 10.0 s in 1 place") == true)
    }

    @Test func overlappingAndReversedCutsAreMerged() {
        let list = EditList(cuts: [
            .init(from: .seconds(5), to: .seconds(12)), .init(from: .seconds(20), to: .seconds(8)), .init(from: .seconds(30), to: .seconds(35)),
        ])
        let (project, _) = apply(list)
        #expect(project.cuts.segments == [TimeSpan(start: 0, end: 5), TimeSpan(start: 20, end: 30), TimeSpan(start: 35, end: 40)])
    }

    @Test func keepRemovesEverythingOutsideTheStretch() {
        let (project, _) = apply(EditList(keep: .init(from: .marker("Loaded"), to: .seconds(30))))
        #expect(project.cuts.segments == [TimeSpan(start: 20, end: 30)])
    }

    @Test func overlaysLandOnTheEditedTimelineAfterCuts() {
        let list = EditList(
            cuts: [.init(from: .marker("Loading"), to: .marker("Loaded"))],
            zooms: [.init(at: .marker("Studio"), duration: 3, x: 0.2, y: 0.7, scale: 2)],
            texts: [.init(text: "Studio", at: .marker("Studio"), duration: 2, position: "top")],
            shapes: [.init(kind: "box", at: .marker("Studio"), duration: 1, x1: 0.1, y1: 0.1, x2: 0.4, y2: 0.3)])
        let (project, outcome) = apply(list)
        // Studio is at 25 s of the original, 15 s after the ten-second cut.
        #expect(project.zooms.map(\.start) == [15])
        #expect(project.zooms.first?.end == 18)
        #expect(project.zooms.first?.x == 0.2)
        #expect(project.texts.first?.start == 15)
        #expect(project.texts.first?.y == 0.12)
        #expect(project.shapes.first?.kind == .box)
        #expect(project.shapes.first?.start == 15)
        #expect(outcome.warnings.isEmpty)
    }

    @Test func aZoomWithoutAPointLooksAtTheNearestClick() {
        let clicks = [ClickEvent(time: 24, x: 0.8, y: 0.25), ClickEvent(time: 3, x: 0.1, y: 0.1)]
        let (project, _) = apply(EditList(zooms: [.init(at: .marker("Studio"))]), clicks: clicks)
        #expect(project.zooms.first?.x == 0.8)
        #expect(project.zooms.first?.y == 0.25)
        let (far, _) = apply(EditList(zooms: [.init(at: .seconds(15))]), clicks: clicks)
        #expect(far.zooms.first?.x == 0.5)
    }

    @Test func thingsInsideACutOrWithUnknownMarkersAreSkippedAndReported() {
        let list = EditList(
            cuts: [.init(from: .marker("Loading"), to: .marker("Loaded"))],
            zooms: [.init(at: .seconds(15)), .init(at: .marker("Missing"))],
            shapes: [.init(kind: "squiggle", at: .seconds(1), x1: 0, y1: 0, x2: 1, y2: 1)])
        let (project, outcome) = apply(list)
        #expect(project.zooms.isEmpty)
        #expect(outcome.warnings.count == 3)
        #expect(outcome.warnings.contains { $0.contains("cut out") })
        #expect(outcome.warnings.contains { $0.contains("No marker named “Missing”") })
        #expect(outcome.warnings.contains { $0.contains("squiggle") })
    }

    @Test func cuttingEverythingIsRefusedNotApplied() {
        let (project, outcome) = apply(EditList(cuts: [.init(from: .seconds(0), to: .seconds(40))]))
        #expect(project.outputDuration == 40)
        #expect(outcome.warnings.count == 1)
    }

    @Test func beatsFollowTheMarkersThroughCutsAndFlagLinesThatAreTooLong() {
        let long = Array(repeating: "word", count: 60).joined(separator: " ")
        let list = EditList(
            cuts: [.init(from: .marker("Loading"), to: .marker("Loaded"))],
            narration: ["Intro": "Welcome to the demo.", "Studio": long, "Nowhere": "x"])
        let (_, outcome) = apply(list)
        // Loading's footage was all cut, so Intro runs to where Loaded now begins.
        #expect(outcome.beats.map(\.name) == ["Intro", "Loaded", "Studio"])
        #expect(outcome.beats.first { $0.name == "Intro" }?.end == 10)
        #expect(outcome.beats.first { $0.name == "Studio" }?.start == 15)
        #expect(outcome.warnings.contains { $0.contains("Nowhere") })
        let script = NarrationScript.markdown(title: "Demo", beats: outcome.beats)
        #expect(script.contains("## 0:00–0:10 · Intro (10 s)"))
        #expect(script.contains("Welcome to the demo."))
        #expect(script.contains("Too long for this part: 60 words"))
        #expect(script.contains("_No narration written for this part._"))
    }

    @Test func anEditListDecodesFromTheJSONAnAgentWrites() throws {
        let json = """
        {"cuts":[{"from":"Loading","to":"Loaded"}],"zooms":[{"at":"Studio","scale":2}],
         "texts":[{"text":"Hi","at":4}],"narration":{"Intro":"Hello"},"chapters":true}
        """
        let list = try JSONDecoder().decode(EditList.self, from: Data(json.utf8))
        #expect(list.cuts?.count == 1)
        #expect(list.zooms?.first?.at == .marker("Studio"))
        #expect(list.texts?.first?.at == .seconds(4))
        #expect(list.chapters == true)
        #expect(list.replace == nil)
    }
}

@Suite struct AgentEditTests {
    private func files() -> TakeFiles {
        TakeFiles(directory: FileManager.default.temporaryDirectory.appendingPathComponent("agent-edit-\(UUID().uuidString)"), baseName: "Take")
    }

    private let markers = [AgentMarker(name: "A", time: 0), AgentMarker(name: "B", time: 10), AgentMarker(name: "C", time: 20)]
    private let list = EditList(
        cuts: [.init(from: .marker("B"), to: .marker("C"))], texts: [.init(text: "Hi", at: .marker("A"))],
        narration: ["A": "Hello there."])

    private func run(_ take: TakeFiles, _ list: EditList) -> Result<AgentEdit.Done, AgentEdit.Failure> {
        AgentEdit.run(list, files: take, duration: 30, camera: nil, title: "Demo", markers: markers, clicks: [])
    }

    @Test func theEditLandsInTheDraftAndTheNarrationIsWrittenBesideTheTake() throws {
        let take = files()
        try FileManager.default.createDirectory(at: take.directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: take.directory) }
        let done = try run(take, list).get()
        #expect(done.project.outputDuration == 20)
        let draft = try #require(StudioDraftStore(files: take).load())
        #expect(draft.project(duration: 30, cameraSource: nil) == done.project)
        let script = try String(contentsOf: try #require(done.narration), encoding: .utf8)
        #expect(script.contains("# Narration script: Demo"))
        #expect(script.contains("Hello there."))
    }

    @Test func existingEditsAreNeverOverwrittenUnlessAskedTo() throws {
        let take = files()
        try FileManager.default.createDirectory(at: take.directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: take.directory) }
        _ = try run(take, list).get()
        guard case .failure(let refused) = run(take, EditList(zooms: [.init(at: .seconds(2))])) else {
            Issue.record("A second edit should have been refused")
            return
        }
        #expect(refused.message.contains("replace"))
        // The first edit is still what is on disk.
        #expect(StudioDraftStore(files: take).load()?.project(duration: 30, cameraSource: nil)?.zooms.isEmpty == true)
        var again = EditList(zooms: [.init(at: .seconds(2))])
        again.replace = true
        let replaced = try run(take, again).get()
        #expect(replaced.project.zooms.count == 1)
        #expect(replaced.project.outputDuration == 30)
    }

    @Test func anEditListThatChangesNothingWritesNothing() {
        let take = files()
        defer { try? FileManager.default.removeItem(at: take.directory) }
        guard case .failure(let failure) = run(take, EditList(zooms: [.init(at: .marker("Nope"))])) else {
            Issue.record("An edit that changes nothing should fail")
            return
        }
        #expect(failure.warnings.count == 1)
        #expect(StudioDraftStore(files: take).load() == nil)
    }
}
