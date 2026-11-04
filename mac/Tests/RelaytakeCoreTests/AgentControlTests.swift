import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct AgentControlTests {
    @Test func aRequestRoundTripsAsOneLine() throws {
        let request = AgentRequest(command: "marker", name: "Open Studio")
        var data = AgentWire.encode(request)
        #expect(data.last == 0x0A)
        let line = try #require(AgentWire.nextLine(in: &data))
        #expect(data.isEmpty)
        #expect(try AgentWire.decodeRequest(line) == request)
    }

    @Test func partialLinesWaitForTheirNewline() throws {
        var buffer = Data("{\"command\":\"pi".utf8)
        #expect(AgentWire.nextLine(in: &buffer) == nil)
        buffer.append(Data("ng\"}\n{\"command\":\"status\"}\n".utf8))
        #expect(try AgentWire.decodeRequest(try #require(AgentWire.nextLine(in: &buffer))).command == "ping")
        #expect(try AgentWire.decodeRequest(try #require(AgentWire.nextLine(in: &buffer))).command == "status")
        #expect(AgentWire.nextLine(in: &buffer) == nil)
    }

    @Test func responsesLeaveOutWhatDoesNotApply() throws {
        let text = String(decoding: AgentWire.encode(AgentResponse(state: "idle")), as: UTF8.self)
        #expect(text == "{\"ok\":true,\"state\":\"idle\"}\n")
        let failure = AgentResponse.failure("Nothing is being recorded.")
        #expect(failure.ok == false)
        #expect(try AgentWire.decodeResponse(Data(AgentWire.encode(failure).dropLast())) == failure)
    }

    @Test func garbageIsRefusedNotCrashed() {
        #expect(throws: (any Error).self) { try AgentWire.decodeRequest(Data("not json".utf8)) }
    }

    @Test func theSocketLivesInThePrivateFolderAndFitsTheSystemLimit() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(AgentPaths.socket(home: home).path == "/Users/someone/Library/Application Support/Hot Take/agent.sock")
        #expect(AgentPaths.isUsable(socket: AgentPaths.socket(home: home)))
        #expect(!AgentPaths.isUsable(socket: URL(fileURLWithPath: "/" + String(repeating: "a", count: 120))))
    }

    @Test func markerNamesAreTidied() {
        #expect(AgentMarkerStore.cleanedName("  Open Studio \nsecond line") == "Open Studio")
        #expect(AgentMarkerStore.cleanedName("   ") == nil)
        #expect(AgentMarkerStore.cleanedName(nil) == nil)
        #expect(AgentMarkerStore.cleanedName(String(repeating: "x", count: 200))?.count == 80)
    }

    @Test func markersSurviveOnDiskAndBecomeChapters() throws {
        let files = TakeFiles(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("markers-\(UUID().uuidString)"), baseName: "Take")
        defer { try? FileManager.default.removeItem(at: files.directory) }
        #expect(AgentMarkerStore.load(for: files).isEmpty)
        let markers = [AgentMarker(name: "Two", time: 9), AgentMarker(name: "One", time: 0.5)]
        try AgentMarkerStore.save(markers, for: files)
        #expect(AgentMarkerStore.load(for: files) == markers)
        #expect(AgentMarkerStore.chapters(from: markers).map(\.title) == ["One", "Two"])
    }
}
