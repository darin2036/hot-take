import Foundation
import RelaytakeCore

/// The same controls as an MCP server on stdin/stdout (one JSON-RPC message per line), so an MCP client such as Claude Desktop
/// or Claude Code can record and edit a demo. Nothing is printed to stdout except protocol messages.
struct MCPServer {
    private struct Tool {
        var name: String
        var description: String
        var properties: [String: [String: Any]] = [:]
        var required: [String] = []
    }

    private static let editDescription = """
        An edit list. Every time is seconds of the ORIGINAL recording, or a marker name (optionally with an offset such as "Open Studio+1.5"). \
        Fields: cuts [{from,to}] remove slow parts; keep {from,to} keeps only that stretch; zooms [{at,duration,x,y,scale}] (x and y are 0-1; \
        omit them to look at the nearest click); texts [{text,at,duration,position:top|center|bottom}]; shapes [{kind:arrow|box|blur,at,duration,x1,y1,x2,y2}]; \
        autoZoom and clickRings (booleans); narration {markerName: "what to say"} for the voice-over script; replace (true to start over).
        """

    private static let tools: [Tool] = [
        Tool(name: "hottake_status", description: "What Hot Take's recorder is doing: idle, recording, paused or busy, with the take's name, elapsed seconds and markers."),
        Tool(name: "hottake_start", description: "Start recording a screen after the usual countdown, and return once recording has begun. The recording bar stays on screen.",
             properties: ["display": ["type": "integer", "description": "Display number from 1. Omit for the screen recorded last."]]),
        Tool(name: "hottake_marker", description: "Name the current moment while recording, for example the start of each step of a demo. Markers become chapters and anchors for edits.",
             properties: ["name": ["type": "string"]], required: ["name"]),
        Tool(name: "hottake_pause", description: "Pause the recording. Paused time is left out of the video."),
        Tool(name: "hottake_resume", description: "Resume a paused recording."),
        Tool(name: "hottake_stop", description: "Stop and save the take. Returns its file, length and markers. Captions are made first, so this can take a while."),
        Tool(name: "hottake_markers", description: "The markers of a take (the live ones while recording).",
             properties: ["take": ["type": "string", "description": "Take file name without extension. Omit for the newest."]]),
        Tool(name: "hottake_edit", description: "Apply an edit list to a take. It lands in the take's Studio draft, where a person can review it. Also writes a narration script with timings. Refuses a take that already has edits unless replace is true. " + editDescription,
             properties: ["take": ["type": "string"], "edit": ["type": "object", "description": editDescription]], required: ["edit"]),
        Tool(name: "hottake_render", description: "Save the take's edits as a new copy in the library (the original is never changed). Markers become chapters unless chapters is false.",
             properties: ["take": ["type": "string"], "chapters": ["type": "boolean"]]),
    ]

    private static let instructions = """
        Hot Take records the Mac's screen. To record a demo: hottake_start, then for each step hottake_marker with a short name and do the step, then hottake_stop. \
        To tighten it: hottake_edit with cuts between markers where the demo waited, zooms on the clicks that matter and captions, then hottake_render. \
        Nothing leaves this Mac. The person must have turned on Settings > Recording > Let local agents control recording.
        """

    func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let data = line.data(using: .utf8), let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                reply(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
                continue
            }
            handle(message)
        }
    }

    private func handle(_ message: [String: Any]) {
        guard let method = message["method"] as? String else { return }  // a response to us; we never ask anything
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]
        guard let id else { return }  // a notification
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? "2024-11-05"
            reply(result(id, [
                "protocolVersion": asked, "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "hottake", "version": version], "instructions": Self.instructions,
            ]))
        case "ping":
            reply(result(id, [String: Any]()))
        case "tools/list":
            let list = Self.tools.map { tool -> [String: Any] in
                ["name": tool.name, "description": tool.description,
                 "inputSchema": ["type": "object", "properties": tool.properties, "required": tool.required] as [String: Any]]
            }
            reply(result(id, ["tools": list]))
        case "tools/call":
            reply(result(id, call(name: params["name"] as? String ?? "", arguments: params["arguments"] as? [String: Any] ?? [:])))
        default:
            reply(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
    }

    private func call(name: String, arguments: [String: Any]) -> [String: Any] {
        func textResult(_ text: String, error: Bool) -> [String: Any] {
            ["content": [["type": "text", "text": text]], "isError": error]
        }
        var request = AgentRequest(command: "")
        switch name {
        case "hottake_status": request.command = "status"
        case "hottake_start":
            request.command = "start"
            request.display = arguments["display"] as? Int
        case "hottake_marker":
            request.command = "marker"
            request.name = arguments["name"] as? String
        case "hottake_pause": request.command = "pause"
        case "hottake_resume": request.command = "resume"
        case "hottake_stop": request.command = "stop"
        case "hottake_markers":
            request.command = "markers"
            request.take = arguments["take"] as? String
        case "hottake_edit":
            request.command = "edit"
            request.take = arguments["take"] as? String
            guard let object = arguments["edit"], JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object)
            else { return textResult("edit must be an edit list object.", error: true) }
            do { request.edit = try JSONDecoder().decode(EditList.self, from: data) } catch {
                return textResult("That is not a valid edit list: \(error)", error: true)
            }
        case "hottake_render":
            request.command = "render"
            request.take = arguments["take"] as? String
            if arguments["chapters"] as? Bool == false { request.edit = EditList(chapters: false) }
        default:
            return textResult("Unknown tool \(name).", error: true)
        }
        do {
            let response = try send(request)
            return textResult(pretty(response), error: !response.ok)
        } catch ClientError.unreachable(let message) {
            return textResult(message, error: true)
        } catch {
            return textResult("\(error)", error: true)
        }
    }

    private func result(_ id: Any, _ value: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": value] }

    private func reply(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data + Data([0x0A]))
    }
}
