import Foundation

// Local control for an agent (Claude Code, Codex, any tool that can run a command or speak MCP): it starts and stops
// a take, drops named markers while it drives the demo, then describes the edit as a list. Everything here is pure
// data and logic. The app listens on a socket only this Mac's user can open (see AgentServer in the app), and
// nothing in this file touches the network.

/// What an agent can ask for.
public enum AgentCommand: String, CaseIterable, Codable, Sendable {
    case ping, status, start, stop, pause, resume, marker, markers, edit, render
}

/// A named moment in a take, in seconds of the recording (paused time is not counted, so it is also a moment of the video).
public struct AgentMarker: Codable, Equatable, Sendable {
    public var name: String
    public var time: Double

    public init(name: String, time: Double) {
        self.name = name
        self.time = time
    }
}

/// One request. Which fields matter depends on `command`.
public struct AgentRequest: Codable, Equatable, Sendable {
    public var command: String
    /// `start`: the display to record (its number, as the CLI lists them). Nil is the screen recorded last.
    public var display: Int?
    /// `marker`: the name of the moment.
    public var name: String?
    /// `markers`, `edit` and `render`: the take, by its file name without extension. Nil is the newest take.
    public var take: String?
    /// `edit`: the changes to make.
    public var edit: EditList?

    public init(command: String, display: Int? = nil, name: String? = nil, take: String? = nil, edit: EditList? = nil) {
        self.command = command
        self.display = display
        self.name = name
        self.take = take
        self.edit = edit
    }
}

/// The answer to one request. Fields that do not apply are left out of the JSON.
public struct AgentResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var error: String?
    /// `idle`, `recording`, `paused` or `busy`.
    public var state: String?
    public var take: String?
    public var video: String?
    public var seconds: Double?
    public var markers: [AgentMarker]?
    public var applied: [String]?
    public var warnings: [String]?
    /// `render`: the copy that was saved.
    public var output: String?
    /// `edit`: the narration script with timings (`narration.md` beside the take's files).
    public var narration: String?

    public init(
        ok: Bool = true, error: String? = nil, state: String? = nil, take: String? = nil, video: String? = nil,
        seconds: Double? = nil, markers: [AgentMarker]? = nil, applied: [String]? = nil, warnings: [String]? = nil,
        output: String? = nil, narration: String? = nil
    ) {
        self.ok = ok
        self.error = error
        self.state = state
        self.take = take
        self.video = video
        self.seconds = seconds
        self.markers = markers
        self.applied = applied
        self.warnings = warnings
        self.output = output
        self.narration = narration
    }

    public static func failure(_ message: String) -> AgentResponse { AgentResponse(ok: false, error: message) }
}

/// One JSON object per line, in both directions. A line longer than `maximumLine` is refused, so a stray process
/// cannot make the app buffer without end.
public enum AgentWire {
    public static let maximumLine = 1_000_000

    public static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = (try? encoder.encode(value)) ?? Data("{\"ok\":false}".utf8)
        data.append(0x0A)
        return data
    }

    public static func decodeRequest(_ line: Data) throws -> AgentRequest {
        try JSONDecoder().decode(AgentRequest.self, from: line)
    }

    public static func decodeResponse(_ line: Data) throws -> AgentResponse {
        try JSONDecoder().decode(AgentResponse.self, from: line)
    }

    /// Removes and returns the first complete line in `buffer`, or nil while there is none yet.
    public static func nextLine(in buffer: inout Data) -> Data? {
        guard let newline = buffer.firstIndex(of: 0x0A) else { return nil }
        let line = buffer[buffer.startIndex..<newline]
        buffer.removeSubrange(buffer.startIndex...newline)
        return Data(line)
    }
}

/// Where the app listens. The folder is the user's own and private; a Unix socket path must stay under about 100 bytes.
public enum AgentPaths {
    public static let maximumSocketPath = 100

    public static func directory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Hot Take", isDirectory: true)
    }

    public static func socket(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        directory(home: home).appendingPathComponent("agent.sock")
    }

    public static func isUsable(socket: URL) -> Bool { socket.path.utf8.count <= maximumSocketPath }
}

/// Markers saved beside a take, so an edit can refer to them after the recording is over.
public enum AgentMarkerStore {
    public static func save(_ markers: [AgentMarker], for files: TakeFiles) throws {
        try FileManager.default.createDirectory(at: files.markers.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(markers).write(to: files.markers, options: .atomic)
    }

    public static func load(for files: TakeFiles) -> [AgentMarker] {
        guard let data = try? Data(contentsOf: files.markers) else { return [] }
        return (try? JSONDecoder().decode([AgentMarker].self, from: data)) ?? []
    }

    /// A name a person or agent gave, tidied: one line, no longer than 80 characters. Nil if nothing is left.
    public static func cleanedName(_ raw: String?) -> String? {
        let line = (raw ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(80))
    }

    /// The markers as chapters of the original recording (the library remaps chapters through cuts when it saves a copy).
    public static func chapters(from markers: [AgentMarker]) -> [Chapter] {
        markers.sorted { $0.time < $1.time }.map { Chapter(start: max(0, $0.time), title: $0.name) }
    }
}
