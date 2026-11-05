import Foundation
import RelaytakeCore

/// What the Connect button in the agent setup window does for each agent: add (or remove) Hot Take's `hottake` server in
/// that agent's own settings, so nobody has to paste a command into Terminal. Nothing runs until the button is clicked.
/// A settings file is copied to `<name>.hottake-backup` before it is changed, and a file that cannot be read as it should be is left alone.
enum AgentConnector {
    enum State: Equatable {
        case notConnected
        case connected
        /// Connected, but to a different copy of Hot Take (the app was moved or rebuilt).
        case otherCopy
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static func supportsConnect(_ client: AgentSetup.Client) -> Bool {
        switch client {
        case .claudeCode, .codex, .rovoDev, .claudeDesktop: true
        case .mcp, .command: false
        }
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// The settings file the entry lives in. For Claude Code that is its own user settings file, which it edits itself.
    static func file(for client: AgentSetup.Client) -> URL? {
        switch client {
        case .claudeCode: home.appendingPathComponent(".claude.json")
        case .codex: home.appendingPathComponent(".codex/config.toml")
        case .rovoDev: home.appendingPathComponent(".rovodev/mcp.json")
        case .claudeDesktop: home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        case .mcp, .command: nil
        }
    }

    /// Where the person is told it was written, with the home folder shown as ~.
    static func displayPath(_ client: AgentSetup.Client) -> String {
        (file(for: client)?.path ?? "").replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    static func restartHint(_ client: AgentSetup.Client) -> String {
        switch client {
        case .claudeCode: "Start a new Claude Code session to use it."
        case .codex: "Restart Codex to use it."
        case .rovoDev: "Start a new Rovo Dev session to use it."
        case .claudeDesktop: "Quit and reopen Claude to use it."
        case .mcp, .command: ""
        }
    }

    static func state(of client: AgentSetup.Client, helper: String) -> State {
        guard let file = file(for: client), let data = try? Data(contentsOf: file) else { return .notConnected }
        let command: String?
        if client == .codex {
            command = AgentConnect.tomlCommand(in: String(decoding: data, as: UTF8.self))
        } else {
            command = AgentConnect.jsonCommand(in: data)
        }
        guard let command else { return .notConnected }
        return command == helper ? .connected : .otherCopy
    }

    // MARK: Connect and disconnect

    /// Returns a sentence saying what was done.
    static func connect(_ client: AgentSetup.Client, helper: String) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: helper) else {
            throw Failure("This copy of Hot Take does not have the hottake command inside it. Build the app with scripts/bundle.sh.")
        }
        if client == .claudeCode {
            try await runClaude(["mcp", "remove", "--scope", "user", "hottake"], allowFailure: true)
            try await runClaude(["mcp", "add", "--scope", "user", "hottake", "--", helper, "mcp"])
        } else {
            try edit(client) { data in
                switch client {
                case .codex:
                    Data(AgentConnect.tomlAdding(to: String(decoding: data ?? Data(), as: UTF8.self), helper: helper).utf8)
                default:
                    try AgentConnect.jsonAdding(to: data, helper: helper, stdioTransport: client == .rovoDev)
                }
            }
        }
        return "Connected. Added to \(displayPath(client)). \(restartHint(client))"
    }

    static func disconnect(_ client: AgentSetup.Client) async throws -> String {
        if client == .claudeCode {
            try await runClaude(["mcp", "remove", "--scope", "user", "hottake"], allowFailure: true)
        } else {
            try edit(client) { data in
                guard let data else { return nil }
                if client == .codex {
                    return Data(AgentConnect.tomlRemoving(from: String(decoding: data, as: UTF8.self)).utf8)
                }
                return try AgentConnect.jsonRemoving(from: data)
            }
        }
        return "Disconnected. Removed from \(displayPath(client))."
    }

    /// Reads the file, lets `change` produce the new contents (nil leaves the file alone), keeps a backup, and writes it.
    private static func edit(_ client: AgentSetup.Client, _ change: (Data?) throws -> Data?) throws {
        guard let file = file(for: client) else { return }
        let fileManager = FileManager.default
        if client == .claudeDesktop, !fileManager.fileExists(atPath: file.deletingLastPathComponent().path) {
            throw Failure("Claude Desktop does not seem to be installed on this Mac. Use Other MCP to copy the settings instead.")
        }
        let existing = try? Data(contentsOf: file)
        guard let updated = try change(existing) else { return }
        try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if existing != nil {
            let backup = file.appendingPathExtension("hottake-backup")
            try? fileManager.removeItem(at: backup)
            try? fileManager.copyItem(at: file, to: backup)
        }
        do {
            try updated.write(to: file, options: .atomic)
        } catch {
            throw Failure("Could not write \(displayPath(client)): \(error.localizedDescription)")
        }
    }

    // MARK: Claude Code's command

    /// The `claude` program. The Claude desktop app keeps its own copy, which is not on the Terminal's search path.
    static func claudeProgram() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        let bundled = home.appendingPathComponent("Library/Application Support/Claude/claude-code")
        let versions = ((try? fileManager.contentsOfDirectory(atPath: bundled.path)) ?? [])
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        for version in versions {
            let folder = bundled.appendingPathComponent(version)
            for inner in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [] {
                candidates.append(folder.appendingPathComponent("\(inner)/claude.app/Contents/MacOS/claude"))
            }
        }
        candidates += [
            home.appendingPathComponent(".claude/local/claude"), home.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"), URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    @discardableResult
    private static func runClaude(_ arguments: [String], allowFailure: Bool = false) async throws -> String {
        guard let program = claudeProgram() else {
            throw Failure("Could not find Claude Code on this Mac. Install the Claude desktop app or Claude Code, or copy the command instead.")
        }
        return try await Task.detached {
            let process = Process()
            process.executableURL = program
            process.arguments = arguments
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: watchdog)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus != 0, !allowFailure {
                throw Failure(text.isEmpty ? "Claude Code could not add Hot Take." : "Claude Code said: \(text)")
            }
            return text
        }.value
    }
}
