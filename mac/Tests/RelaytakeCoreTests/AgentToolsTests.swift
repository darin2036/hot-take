import CoreGraphics
import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct AgentToolsTests {
    // MARK: Displays

    @Test func displaysAreNumberedFromOneAndMovedToTheMouseSpace() {
        // The system puts the origin at the bottom-left of the main display; a screen above it has a larger y.
        let list = AgentDisplays.list([
            .init(name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), scale: 2),
            .init(name: "Sceptre", frame: CGRect(x: -120, y: 1169, width: 1920, height: 1080), scale: 1),
        ])
        #expect(list.map(\.number) == [1, 2])
        #expect(list[0].isMain && !list[1].isMain)
        #expect(list[0].x == 0 && list[0].y == 0)
        // Above the main display means a negative y when the origin is top-left.
        #expect(list[1].x == -120 && list[1].y == -1080)
        #expect(AgentDisplays.list([]).isEmpty)
    }

    @Test func aPointOnADisplayBecomesADesktopPointOrNilWhenOffIt() throws {
        let display = AgentDisplay(number: 2, name: "Sceptre", x: -120, y: -1080, width: 1920, height: 1080, scale: 1, isMain: false)
        let point = try #require(display.desktopPoint(x: 100, y: 50))
        #expect(point.x == -20 && point.y == -1030)
        #expect(display.desktopPoint(x: 1920, y: 0) == nil)
        #expect(display.desktopPoint(x: -1, y: 10) == nil)
        #expect(display.desktopPoint(x: .nan, y: 10) == nil)
    }

    @Test func aDisplayEncodesWithTheKeyMain() throws {
        let display = AgentDisplay(number: 1, name: "A", x: 0, y: 0, width: 10, height: 10, scale: 2, isMain: true)
        let text = String(decoding: try JSONEncoder().encode(display), as: UTF8.self)
        #expect(text.contains("\"main\":true"))
        #expect(try JSONDecoder().decode(AgentDisplay.self, from: Data(text.utf8)) == display)
    }

    // MARK: Retakes

    @Test func aRetakeCutsTheFailedAttemptAndTakesOverTheName() {
        let markers = [
            AgentMarker(name: "Open", time: 0), AgentMarker(name: "Watch", time: 10),
            AgentMarker(name: "Retake: Watch", time: 30), AgentMarker(name: "Studio", time: 45),
        ]
        let result = AgentRetakes.resolve(markers)
        #expect(result.cuts == [TimeSpan(start: 10, end: 30)])
        #expect(result.markers.map(\.name) == ["Open", "Watch", "Studio"])
        #expect(result.markers.map(\.time) == [0, 30, 45])
        #expect(result.warnings.isEmpty)
    }

    @Test func aBeatRedoneTwiceKeepsOnlyTheLastAttempt() {
        let markers = [
            AgentMarker(name: "Watch", time: 5), AgentMarker(name: "retake:  watch", time: 20), AgentMarker(name: "Retake: Watch", time: 40),
        ]
        let result = AgentRetakes.resolve(markers)
        #expect(result.cuts == [TimeSpan(start: 5, end: 20), TimeSpan(start: 20, end: 40)])
        #expect(result.markers == [AgentMarker(name: "Watch", time: 40)])
    }

    @Test func aRetakeWithNothingToRedoIsRenamedAndWarnedAbout() {
        let result = AgentRetakes.resolve([AgentMarker(name: "Retake: Export", time: 12)])
        #expect(result.cuts.isEmpty)
        #expect(result.markers == [AgentMarker(name: "Export", time: 12)])
        #expect(result.warnings.count == 1)
    }

    @Test func onlyTheRetakePrefixCounts() {
        #expect(AgentRetakes.beatName(of: "Retake: Open Studio") == "Open Studio")
        #expect(AgentRetakes.beatName(of: "Retake:") == nil)
        #expect(AgentRetakes.beatName(of: "Retaken photos") == nil)
        #expect(AgentRetakes.beatName(of: "Studio") == nil)
    }

    @Test func theEditCutsRetakesByItselfAndKeepsTheNarrationUnderTheBeatName() {
        let markers = [
            AgentMarker(name: "Open", time: 0), AgentMarker(name: "Watch", time: 10),
            AgentMarker(name: "Retake: Watch", time: 30), AgentMarker(name: "End", time: 45),
        ]
        let list = EditList(narration: ["Retake: Watch": "Open a take to watch it."])
        let (project, outcome) = EditListApplier.apply(list, to: StudioProject(duration: 60), markers: markers, clicks: [])
        #expect(project.cuts.segments == [TimeSpan(start: 0, end: 10), TimeSpan(start: 30, end: 60)])
        #expect(outcome.warnings.isEmpty)
        #expect(outcome.beats.map(\.name) == ["Open", "Watch", "End"])
        #expect(outcome.beats.first { $0.name == "Watch" }?.text == "Open a take to watch it.")
        #expect(outcome.applied.contains { $0.contains("failed attempt") })

        var off = list
        off.autoRetakes = false
        let (untouched, _) = EditListApplier.apply(off, to: StudioProject(duration: 60), markers: markers, clicks: [])
        #expect(!untouched.isEdited)
    }

    // MARK: Zooms

    @Test func zoomsAreThinnedToTheLimitAndStayInOrder() {
        let zooms = (0..<10).map { ZoomSegment(start: Double($0) * 4, end: Double($0) * 4 + 2) }
        // At most 6 a minute means a gap of 10 seconds: 0, 12, 24, 36.
        #expect(ZoomCap.thinned(zooms, maxPerMinute: 6).map(\.start) == [0, 12, 24, 36])
        #expect(ZoomCap.thinned(zooms, maxPerMinute: 0).count == 10)
        #expect(ZoomCap.thinned([], maxPerMinute: 6).isEmpty)
    }

    @Test func autoZoomCanBeCappedInTheEdit() {
        let clicks = (0..<10).map { ClickEvent(time: Double($0) * 10 + 1, x: 0.5, y: 0.5) }
        let unlimited = EditListApplier.apply(EditList(autoZoom: true), to: StudioProject(duration: 120), markers: [], clicks: clicks).0
        let capped = EditListApplier.apply(
            EditList(autoZoom: true, maxZoomsPerMinute: 2), to: StudioProject(duration: 120), markers: [], clicks: clicks)
        #expect(unlimited.zooms.count > capped.0.zooms.count)
        #expect(capped.0.zooms.count <= 4)
        #expect(capped.1.applied.contains { $0.hasPrefix("Kept ") })
    }

    // MARK: Pictures

    @Test func requestedMomentsAreClampedSortedAndDeduplicated() {
        let times = AgentFrames.times(requested: [50, 3, 3.05, -1], chapterStarts: [], duration: 20)
        #expect(times == [0, 3, 19.95])
        #expect(AgentFrames.times(requested: [1], chapterStarts: [], duration: 0).isEmpty)
    }

    @Test func withoutRequestsThereIsOnePicturePerChapterThenEvenSpread() {
        let chapters = AgentFrames.times(requested: [], chapterStarts: [0, 10, 30], duration: 40)
        #expect(chapters == [5, 20, 35])
        let even = AgentFrames.times(requested: [], chapterStarts: [], duration: 12, count: 4)
        #expect(even == [1.5, 4.5, 7.5, 10.5])
        #expect(AgentFrames.times(requested: [], chapterStarts: [], duration: 1000, count: 500).count == AgentFrames.maximum)
    }

    @Test func aShortChapterGetsItsPictureInsideIt() {
        // A one-second chapter starting at 0: the picture is half a second in, not on the next chapter.
        #expect(AgentFrames.times(requested: [], chapterStarts: [0, 1, 20], duration: 30) == [0.5, 10.5, 25])
    }

    @Test func pictureNamesSortInOrderAndSheetsGetSensibleColumns() {
        #expect(AgentFrames.fileName(number: 3, of: 12, time: 72.4) == "Frame 03 at 1m12s.png")
        #expect(AgentFrames.columns(for: 3) == 2)
        #expect(AgentFrames.columns(for: 7) == 3)
        #expect(AgentFrames.columns(for: 12) == 4)
    }

    @Test func aFindingHidesTheTextItReports() {
        let sighting = SensitiveSighting(
            kind: .email, text: "darin@example.com", time: 2, rect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05))
        let finding = AgentFinding(sighting)
        #expect(finding.kind == "Email address")
        #expect(!finding.preview.contains("example"))
        #expect(finding.x == 0.1 && finding.height == 0.05 && finding.time == 2)
    }

    // MARK: Protocol

    @Test func newRequestAndResponseFieldsRoundTripAndOldOnesStayOut() throws {
        let request = AgentRequest(command: "frames", take: "T", times: [1, 2.5], scan: true, terms: ["Acme"], width: 1200)
        var data = AgentWire.encode(request)
        #expect(try AgentWire.decodeRequest(try #require(AgentWire.nextLine(in: &data))) == request)

        let display = AgentDisplay(number: 1, name: "A", x: 0, y: 0, width: 10, height: 10, scale: 2, isMain: true)
        let response = AgentResponse(
            displays: [display], inputAllowed: false, apps: ["Hot Take"],
            findings: [AgentFinding(kind: "Email address", preview: "da•••••", time: 0, x: 0, y: 0, width: 1, height: 1)],
            frames: [AgentFrame(time: 1, path: "/tmp/a.png")], contactSheet: "/tmp/sheet.png", discarded: ["T"])
        var out = AgentWire.encode(response)
        #expect(try AgentWire.decodeResponse(try #require(AgentWire.nextLine(in: &out))) == response)

        // A marker request with no new fields still encodes to just what it had before.
        let plain = String(decoding: AgentWire.encode(AgentRequest(command: "marker", name: "A")), as: UTF8.self)
        #expect(plain == "{\"command\":\"marker\",\"name\":\"A\"}\n")
    }

    @Test func everyCommandIsKnown() {
        for name in ["displays", "screenshot", "preflight", "frames", "discard", "window"] {
            #expect(AgentCommand(rawValue: name) != nil)
        }
    }
}
