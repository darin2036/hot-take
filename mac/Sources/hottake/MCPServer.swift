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
        autoZoom and clickRings (booleans); maxZoomsPerMinute (caps the automatic zooms); narration {markerName: "what to say"} for the voice-over script; \
        narrationCaptions (true turns the narration lines into captions drawn in the video, a captions file and the saved copy's transcript, so a demo with no spoken audio is still readable; \
        with captionStyle classic|bold|minimal|highlight and captionPosition bottom|middle|top); \
        autoRetakes (on by default: a "Retake: Name" marker cuts the failed attempt at "Name" and keeps its narration); replace (true to start over).
        """

    private static let tools: [Tool] = [
        Tool(name: "hottake_status", description: "What Hot Take's recorder is doing: idle, recording, paused or busy, with the take's name, elapsed seconds and markers."),
        Tool(name: "hottake_displays", description: "Every display with its number, name and position and size in points. Use the position to aim clicks, and the number to choose what to record."),
        Tool(name: "hottake_screenshot", description: "A picture of a screen without recording, saved as a PNG whose path is returned. Use it to see the app you are driving.",
             properties: ["display": ["type": "integer", "description": "Display number from 1. Omit for the screen recorded last."],
                          "width": ["type": "integer", "description": "Widest the picture should be in pixels (default 1600)."]]),
        Tool(name: "hottake_preflight", description: "Before recording: which apps have windows on a display, and whether text that looks sensitive (emails, keys, phone numbers, addresses, and any words you list) is showing. Run it first and clear the screen if it warns.",
             properties: ["display": ["type": "integer"], "terms": ["type": "array", "items": ["type": "string"], "description": "Extra words to treat as sensitive."]]),
        Tool(name: "hottake_window", description: "Put Hot Take's window on a display, large and centered, so a demo of Hot Take happens on the screen being recorded.",
             properties: ["display": ["type": "integer"]]),
        Tool(name: "hottake_start", description: "Start recording a screen after the usual countdown, and return once recording has begun. The recording bar stays on screen.",
             properties: ["display": ["type": "integer", "description": "Display number from 1. Omit for the screen recorded last."]]),
        Tool(name: "hottake_marker", description: "Name the current moment while recording, for example the start of each step of a demo. Markers become chapters and anchors for edits.",
             properties: ["name": ["type": "string"], "back": ["type": "number", "description": "Place the marker this many seconds earlier, for a step already under way."]], required: ["name"]),
        Tool(name: "hottake_retake", description: "A step went wrong and you are redoing it: marks the redo. The edit cuts the failed attempt at that step by itself and the redo keeps the step's name, narration and chapter. Do not stop the recording.",
             properties: ["name": ["type": "string", "description": "The name of the step you are redoing."]], required: ["name"]),
        Tool(name: "hottake_pause", description: "Pause the recording. Paused time is left out of the video."),
        Tool(name: "hottake_resume", description: "Resume a paused recording."),
        Tool(name: "hottake_stop", description: "Stop and save the take. Returns its file, length and markers. Captions are made first, so this can take a while."),
        Tool(name: "hottake_markers", description: "The markers of a take (the live ones while recording).",
             properties: ["take": ["type": "string", "description": "Take file name without extension. Omit for the newest."]]),
        Tool(name: "hottake_edit", description: "Apply an edit list to a take. It lands in the take's Studio draft, where a person can review it. Also writes a narration script with timings. Refuses a take that already has edits unless replace is true. " + editDescription,
             properties: ["take": ["type": "string"], "edit": ["type": "object", "description": editDescription]], required: ["edit"]),
        Tool(name: "hottake_frames", description: "Pictures from a video (the last saved copy by default) plus one contact sheet laying them out, so you can check captions, zooms and framing without watching. With scan, also looks for text that looks sensitive in those pictures.",
             properties: ["take": ["type": "string"], "times": ["type": "array", "items": ["type": "number"], "description": "Seconds of the video. Omit for one picture from the middle of each chapter."],
                          "scan": ["type": "boolean"], "terms": ["type": "array", "items": ["type": "string"]]]),
        Tool(name: "hottake_discard", description: "Move a take you recorded (or a copy you saved) to the Trash. It refuses takes a person recorded, and never deletes permanently.",
             properties: ["take": ["type": "string"]], required: ["take"]),
        Tool(name: "hottake_move", description: "Glide the pointer to a position. Needs the person to have turned on Settings > Recording > Also let agents use the mouse and keyboard.",
             properties: ["x": ["type": "number"], "y": ["type": "number"], "display": ["type": "integer", "description": "If given, x and y are points from that display's top-left."]], required: ["x", "y"]),
        Tool(name: "hottake_click", description: "Glide the pointer there and click (real mouse events, so Hot Take notes the click for zooms and rings). Same permission as hottake_move.",
             properties: ["x": ["type": "number"], "y": ["type": "number"], "display": ["type": "integer"], "double": ["type": "boolean"]], required: ["x", "y"]),
        Tool(name: "hottake_drag", description: "Press at one position, drag to another and release. Same permission as hottake_move.",
             properties: ["x1": ["type": "number"], "y1": ["type": "number"], "x2": ["type": "number"], "y2": ["type": "number"], "display": ["type": "integer"]],
             required: ["x1", "y1", "x2", "y2"]),
        Tool(name: "hottake_key", description: "Press a key or combination such as return, escape, tab, space, left, or cmd+shift+s. Same permission as hottake_move.",
             properties: ["keys": ["type": "string"]], required: ["keys"]),
        Tool(name: "hottake_type", description: "Type text as it is (up to 2000 characters). Same permission as hottake_move.",
             properties: ["text": ["type": "string"]], required: ["text"]),
        Tool(name: "hottake_render", description: "Save the take's edits as a new copy in the library (the original is never changed). Markers become chapters unless chapters is false.",
             properties: ["take": ["type": "string"], "chapters": ["type": "boolean"]]),
    ]

    private static let instructions = """
        Hot Take records the Mac's screen. To record a demo: hottake_displays, hottake_preflight (clear the screen if it warns), hottake_start, then for each step hottake_marker \
        with a short name and do the step (hottake_retake if it goes wrong), then hottake_stop. After rendering, hottake_frames shows what the video looks like. \
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
        case "hottake_displays": request.command = "displays"
        case "hottake_screenshot", "hottake_preflight", "hottake_window":
            request.command = String(name.dropFirst("hottake_".count))
            request.display = intValue(arguments["display"])
            request.width = intValue(arguments["width"])
            request.terms = arguments["terms"] as? [String]
        case "hottake_frames":
            request.command = "frames"
            request.take = arguments["take"] as? String
            request.times = (arguments["times"] as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue }
            request.scan = arguments["scan"] as? Bool
            request.terms = arguments["terms"] as? [String]
        case "hottake_discard":
            request.command = "discard"
            request.take = arguments["take"] as? String
        case "hottake_retake":
            request.command = "marker"
            guard let beat = (arguments["name"] as? String)?.trimmingCharacters(in: .whitespaces), !beat.isEmpty else {
                return textResult("retake needs the name of the step you are redoing.", error: true)
            }
            request.name = "\(AgentRetakes.prefix) \(beat)"
        case "hottake_move", "hottake_click", "hottake_drag", "hottake_key", "hottake_type":
            guard let action = inputAction(name, arguments) else { return textResult("Missing or invalid arguments for \(name).", error: true) }
            let response = performInput(action, send: send)
            return textResult(pretty(response), error: !response.ok)
        case "hottake_marker":
            request.command = "marker"
            request.name = arguments["name"] as? String
            request.back = (arguments["back"] as? NSNumber)?.doubleValue
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

    private func intValue(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }

    private func inputAction(_ name: String, _ arguments: [String: Any]) -> InputAction? {
        func number(_ key: String) -> Double? { (arguments[key] as? NSNumber)?.doubleValue }
        let display = intValue(arguments["display"])
        switch name {
        case "hottake_move":
            guard let x = number("x"), let y = number("y") else { return nil }
            return .move(x: x, y: y, display: display)
        case "hottake_click":
            guard let x = number("x"), let y = number("y") else { return nil }
            return .click(x: x, y: y, display: display, double: arguments["double"] as? Bool ?? false)
        case "hottake_drag":
            guard let x1 = number("x1"), let y1 = number("y1"), let x2 = number("x2"), let y2 = number("y2") else { return nil }
            return .drag(x1: x1, y1: y1, x2: x2, y2: y2, display: display)
        case "hottake_key":
            return (arguments["keys"] as? String).map(InputAction.key)
        default:
            return (arguments["text"] as? String).map(InputAction.type)
        }
    }

    private func result(_ id: Any, _ value: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": value] }

    private func reply(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data + Data([0x0A]))
    }
}
