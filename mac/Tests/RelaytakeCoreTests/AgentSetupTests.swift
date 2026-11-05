import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct AgentSetupTests {
    private let helper = "/Applications/Hot Take.app/Contents/Helpers/hottake"

    @Test func shellQuotingSurvivesSpacesAndQuotes() {
        #expect(AgentSetup.shellQuoted("/a b/c") == "'/a b/c'")
        #expect(AgentSetup.shellQuoted("it's") == "'it'\\''s'")
    }

    @Test func everyClientGetsAnInstructionAndAPathThatIsQuotedForIt() {
        let claude = AgentSetup.snippet(for: .claudeCode, helper: helper)
        #expect(claude.text == "claude mcp add --scope user hottake -- '/Applications/Hot Take.app/Contents/Helpers/hottake' mcp")
        let codex = AgentSetup.snippet(for: .codex, helper: helper)
        #expect(codex.text.contains("[mcp_servers.hottake]"))
        #expect(codex.text.contains("command = \"/Applications/Hot Take.app/Contents/Helpers/hottake\""))
        #expect(codex.text.contains("args = [\"mcp\"]"))
        let command = AgentSetup.snippet(for: .command, helper: helper)
        #expect(command.text.hasSuffix(" status"))
        for client in AgentSetup.Client.allCases {
            #expect(!AgentSetup.snippet(for: client, helper: helper).instruction.isEmpty)
        }
    }

    @Test func theMCPSnippetIsValidJSONEvenWithAwkwardPaths() throws {
        let awkward = "/Users/Some \"One\"/Hot Take.app/Contents/Helpers/hottake"
        let text = AgentSetup.snippet(for: .mcp, helper: awkward).text
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let server = try #require((object["mcpServers"] as? [String: Any])?["hottake"] as? [String: Any])
        #expect(server["command"] as? String == awkward)
        #expect(server["args"] as? [String] == ["mcp"])
    }

    @Test func theRovoDevSnippetIsValidJSONWithAStdioTransport() throws {
        let text = AgentSetup.snippet(for: .rovoDev, helper: helper).text
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let server = try #require((object["mcpServers"] as? [String: Any])?["hottake"] as? [String: Any])
        #expect(server["command"] as? String == helper)
        #expect(server["args"] as? [String] == ["mcp"])
        #expect(server["transport"] as? String == "stdio")
    }

    @Test func thePromptNamesTheTopicTheSkillAndTheCommandAndAsksForAPlanFirst() {
        let prompt = AgentSetup.prompt(topic: " the export dialog ", helper: helper, skill: "/skills/demo-recording/SKILL.md")
        #expect(prompt.contains("demo video of the export dialog."))
        #expect(prompt.contains("/skills/demo-recording/SKILL.md"))
        #expect(prompt.contains(helper))
        #expect(prompt.contains("wait for my OK"))
        let bare = AgentSetup.prompt(topic: "  ", helper: helper, skill: nil)
        #expect(bare.contains("the app we are working on"))
        #expect(!bare.contains("demo-recording skill"))
    }
}
