import Foundation

// The edits the "Connect" buttons in the agent setup window make to other apps' settings files: adding or removing
// the `hottake` server and nothing else. Pure text and JSON in, text and JSON out, so it can be tested. The app
// does the file reading, backing up and writing.

public enum AgentConnect {
    public enum ConnectError: LocalizedError {
        case unreadable(String)
        public var errorDescription: String? {
            switch self {
            case .unreadable(let file): "\(file) is not in a form Hot Take can safely edit, so it was left alone."
            }
        }
    }

    // MARK: JSON settings (Claude Desktop, Rovo Dev, Claude Code's own settings)

    private static func object(_ data: Data?) throws -> [String: Any] {
        guard let data, !data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConnectError.unreadable("This settings file")
        }
        return object
    }

    private static func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// `existing` with the `hottake` server added (or replaced) under `mcpServers`; everything else is kept.
    public static func jsonAdding(to existing: Data?, helper: String, stdioTransport: Bool = false) throws -> Data {
        var root = try object(existing)
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        var entry: [String: Any] = ["command": helper, "args": ["mcp"]]
        if stdioTransport { entry["transport"] = "stdio" }
        servers["hottake"] = entry
        root["mcpServers"] = servers
        return try encode(root)
    }

    /// `existing` without the `hottake` server. Other servers and settings are kept.
    public static func jsonRemoving(from existing: Data) throws -> Data {
        var root = try object(existing)
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers["hottake"] = nil
        root["mcpServers"] = servers
        return try encode(root)
    }

    /// The command the `hottake` server is set to run, if it is set.
    public static func jsonCommand(in existing: Data?) -> String? {
        guard let root = try? object(existing),
              let server = (root["mcpServers"] as? [String: Any])?["hottake"] as? [String: Any]
        else { return nil }
        return server["command"] as? String
    }

    // MARK: TOML settings (Codex)

    private static let header = "[mcp_servers.hottake]"

    private static func startsSection(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).hasPrefix("[") }

    private static func isOurs(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == header || trimmed.hasPrefix("[mcp_servers.hottake.")
    }

    /// Lines with our section (and its sub-tables) taken out, trailing blank lines trimmed.
    private static func withoutSection(_ text: String) -> [String] {
        var kept: [String] = []
        var skipping = false
        for line in text.components(separatedBy: "\n") {
            if startsSection(line) { skipping = isOurs(line) }
            if !skipping { kept.append(line) }
        }
        while kept.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { kept.removeLast() }
        return kept
    }

    public static func tomlAdding(to existing: String, helper: String) -> String {
        var lines = withoutSection(existing)
        if !lines.isEmpty { lines.append("") }
        lines += [header, "command = \(AgentSetup.quoted(helper))", "args = [\"mcp\"]"]
        return lines.joined(separator: "\n") + "\n"
    }

    public static func tomlRemoving(from existing: String) -> String {
        let lines = withoutSection(existing)
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    public static func tomlCommand(in existing: String) -> String? {
        var inside = false
        for line in existing.components(separatedBy: "\n") {
            if startsSection(line) { inside = line.trimmingCharacters(in: .whitespaces) == header; continue }
            guard inside else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("command"), let equals = trimmed.firstIndex(of: "=") else { continue }
            var value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard value.hasPrefix("\""), let close = value.dropFirst().lastIndex(of: "\"") else { continue }
            value = String(value[value.index(after: value.startIndex)..<close])
            return value.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
        }
        return nil
    }
}
