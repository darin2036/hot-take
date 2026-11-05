import Foundation

// Local control for an agent (Claude Code, Codex, any tool that can run a command or speak MCP): it starts and stops
// a take, drops named markers while it drives the demo, then describes the edit as a list. Everything here is pure
// data and logic. The app listens on a socket only this Mac's user can open (see AgentServer in the app), and
// nothing in this file touches the network.

/// What an agent can ask for.
public enum AgentCommand: String, CaseIterable, Codable, Sendable {
    case ping, status, start, stop, pause, resume, marker, markers, edit, render
    /// Where each display is, for aiming clicks and choosing which to record.
    case displays
    /// One picture of a screen, without recording, for the agent to look at.
    case screenshot
    /// Look at a screen before recording: which apps have windows on it, and whether sensitive text is showing.
    case preflight
    /// Pictures from a finished video (and an optional sensitive-text check of them) so an agent can verify an edit.
    case frames
    /// Move an agent's own test take to the Trash.
    case discard
    /// Put Hot Take's window on a chosen display.
    case window
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

/// One picture taken from a video: where it is and which second it shows.
public struct AgentFrame: Codable, Equatable, Sendable {
    public var time: Double
    public var path: String
    public init(time: Double, path: String) { self.time = time; self.path = path }
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
    /// `marker`: place the marker this many seconds before now (for a step already begun).
    public var back: Double?
    /// `frames`: the moments to take pictures of, in seconds of the video.
    public var times: [Double]?
    /// `frames`: also look for sensitive text in the pictures.
    public var scan: Bool?
    /// `preflight` and `frames` with `scan`: extra words to treat as sensitive (a name, a client, a hostname).
    public var terms: [String]?
    /// `screenshot`: the widest the picture should be, in pixels (it is only ever scaled down).
    public var width: Int?

    public init(
        command: String, display: Int? = nil, name: String? = nil, take: String? = nil, edit: EditList? = nil,
        back: Double? = nil, times: [Double]? = nil, scan: Bool? = nil, terms: [String]? = nil, width: Int? = nil
    ) {
        self.command = command
        self.display = display
        self.name = name
        self.take = take
        self.edit = edit
        self.back = back
        self.times = times
        self.scan = scan
        self.terms = terms
        self.width = width
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
    /// `displays`: every display, numbered as `start --display` numbers them.
    public var displays: [AgentDisplay]?
    /// `ping` and `status`: whether the person also let agents use the mouse and keyboard (Settings ▸ Recording).
    public var inputAllowed: Bool?
    /// `screenshot`: the PNG that was saved (in a private folder, removed after a day).
    public var image: String?
    /// `preflight`: the apps with windows on that display.
    public var apps: [String]?
    /// `preflight` and `frames` with `scan`: sensitive text that was seen, with most of each hidden.
    public var findings: [AgentFinding]?
    /// `frames`: the pictures, in order, and the contact sheet that lays them out together.
    public var frames: [AgentFrame]?
    public var contactSheet: String?
    /// `discard`: the takes moved to the Trash.
    public var discarded: [String]?

    public init(
        ok: Bool = true, error: String? = nil, state: String? = nil, take: String? = nil, video: String? = nil,
        seconds: Double? = nil, markers: [AgentMarker]? = nil, applied: [String]? = nil, warnings: [String]? = nil,
        output: String? = nil, narration: String? = nil, displays: [AgentDisplay]? = nil, inputAllowed: Bool? = nil,
        image: String? = nil, apps: [String]? = nil, findings: [AgentFinding]? = nil, frames: [AgentFrame]? = nil,
        contactSheet: String? = nil, discarded: [String]? = nil
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
        self.displays = displays
        self.inputAllowed = inputAllowed
        self.image = image
        self.apps = apps
        self.findings = findings
        self.frames = frames
        self.contactSheet = contactSheet
        self.discarded = discarded
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
