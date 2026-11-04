import Foundation

// The text the in-app "Let an agent record a demo" sheet hands a person to paste: how to connect each kind of agent to the
// `hottake` command inside the app, and a first message to give the agent. Pure text, so it can be tested.

public enum AgentSetup {
    public enum Client: String, CaseIterable, Identifiable, Sendable {
        case claudeCode = "Claude Code"
        case codex = "Codex"
        case rovoDev = "Rovo Dev"
        case mcp = "Other MCP"
        case command = "Terminal"

        public var id: String { rawValue }
    }

    public struct Snippet: Equatable, Sendable {
        /// What to do with `text`, in a sentence.
        public var instruction: String
        public var text: String
    }

    /// A word for a shell: wrapped in single quotes so spaces and symbols in the path are safe.
    public static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A TOML or JSON basic string: double quotes, with backslashes and quotes escaped.
    static func quoted(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }

    public static func snippet(for client: Client, helper: String) -> Snippet {
        switch client {
        case .claudeCode:
            return Snippet(
                instruction: "Paste this into Terminal once, then start a new Claude Code session.",
                text: "claude mcp add hottake -- \(shellQuoted(helper)) mcp")
        case .codex:
            return Snippet(
                instruction: "Add this to ~/.codex/config.toml, then restart Codex.",
                text: "[mcp_servers.hottake]\ncommand = \(quoted(helper))\nargs = [\"mcp\"]")
        case .rovoDev:
            return Snippet(
                instruction: "Add this to ~/.rovodev/mcp.json (Terminal: acli rovodev mcp opens it), then start a new Rovo Dev session. This is the command-line Rovo Dev; browser Rovo cannot reach your Mac.",
                text: "{\n  \"mcpServers\": {\n    \"hottake\": {\n      \"command\": \(quoted(helper)),\n      \"args\": [\"mcp\"],\n      \"transport\": \"stdio\"\n    }\n  }\n}")
        case .mcp:
            return Snippet(
                instruction: "Add this to your app's MCP server settings, then restart it. In Claude Desktop that is Settings ▸ Developer ▸ Edit Config.",
                text: "{\n  \"mcpServers\": {\n    \"hottake\": {\n      \"command\": \(quoted(helper)),\n      \"args\": [\"mcp\"]\n    }\n  }\n}")
        case .command:
            return Snippet(
                instruction: "Any agent that can run commands can use this one. Try it yourself in Terminal.",
                text: "\(shellQuoted(helper)) status")
        }
    }

    /// The first message to give an agent. `topic` is what the person wants shown; `skill` is the demo-recording skill file.
    public static func prompt(topic: String, helper: String, skill: String?) -> String {
        let what = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = "Use Hot Take to record a demo video of \(what.isEmpty ? "the app we are working on" : what)."
        if let skill { text += "\n\nFirst read the demo-recording skill at \(skill)." }
        text += """

            Then propose a plan (the steps to show and what to say at each) and wait for my OK before you record anything. \
            You drive the app yourself; Hot Take only records and edits. Use the hottake tools if they are connected, \
            or run the command at \(helper). When the recording is done, tighten it and save it, and tell me where the \
            video and the narration script are.
            """
        return text
    }
}
