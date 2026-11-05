import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct AgentConnectTests {
    private let helper = "/Applications/Hot Take.app/Contents/Helpers/hottake"

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func addingToJSONKeepsEverythingElse() throws {
        let existing = Data(#"{"theme":"dark","mcpServers":{"other":{"command":"x"}}}"#.utf8)
        let result = try json(AgentConnect.jsonAdding(to: existing, helper: helper))
        #expect(result["theme"] as? String == "dark")
        let servers = try #require(result["mcpServers"] as? [String: Any])
        #expect(servers["other"] != nil)
        #expect((servers["hottake"] as? [String: Any])?["command"] as? String == helper)
    }

    @Test func addingToNothingOrAnEmptyFileCreatesTheEntryAndAddingTwiceReplacesIt() throws {
        let first = try AgentConnect.jsonAdding(to: nil, helper: "/old/hottake")
        #expect(AgentConnect.jsonCommand(in: first) == "/old/hottake")
        let second = try AgentConnect.jsonAdding(to: first, helper: helper, stdioTransport: true)
        #expect(AgentConnect.jsonCommand(in: second) == helper)
        let server = try #require((try json(second)["mcpServers"] as? [String: Any])?["hottake"] as? [String: Any])
        #expect(server["transport"] as? String == "stdio")
        #expect(try AgentConnect.jsonAdding(to: Data("  \n".utf8), helper: helper).count > 0)
    }

    @Test func aFileThatIsNotAJSONObjectIsNeverOverwritten() {
        #expect(throws: AgentConnect.ConnectError.self) { try AgentConnect.jsonAdding(to: Data("not json".utf8), helper: helper) }
        #expect(throws: AgentConnect.ConnectError.self) { try AgentConnect.jsonAdding(to: Data("[1]".utf8), helper: helper) }
    }

    @Test func removingFromJSONLeavesOtherServers() throws {
        let both = try AgentConnect.jsonAdding(to: Data(#"{"mcpServers":{"other":{"command":"x"}}}"#.utf8), helper: helper)
        let removed = try AgentConnect.jsonRemoving(from: both)
        #expect(AgentConnect.jsonCommand(in: removed) == nil)
        #expect(((try json(removed))["mcpServers"] as? [String: Any])?["other"] != nil)
    }

    @Test func tomlAddReplaceAndRemoveTouchOnlyOurSection() {
        let existing = "model = \"x\"\n\n[mcp_servers.other]\ncommand = \"o\"\n"
        let added = AgentConnect.tomlAdding(to: existing, helper: helper)
        #expect(added.contains("model = \"x\"") && added.contains("[mcp_servers.other]\ncommand = \"o\""))
        #expect(AgentConnect.tomlCommand(in: added) == helper)
        let replaced = AgentConnect.tomlAdding(to: added, helper: "/new/hottake")
        #expect(AgentConnect.tomlCommand(in: replaced) == "/new/hottake")
        #expect(replaced.components(separatedBy: "[mcp_servers.hottake]").count == 2)
        let removed = AgentConnect.tomlRemoving(from: replaced)
        #expect(AgentConnect.tomlCommand(in: removed) == nil)
        #expect(removed.contains("[mcp_servers.other]") && removed.contains("model = \"x\""))
    }

    @Test func tomlWithOurSectionInTheMiddleKeepsTheSectionsAfterIt() {
        let text = "[mcp_servers.hottake]\ncommand = \"a\"\nargs = [\"mcp\"]\n[mcp_servers.hottake.env]\nA = \"1\"\n\n[tui]\nx = 1\n"
        let removed = AgentConnect.tomlRemoving(from: text)
        #expect(removed == "[tui]\nx = 1\n")
    }
}
