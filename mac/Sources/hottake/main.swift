import Darwin
import Foundation
import RelaytakeCore

// `hottake`: the command an agent runs to drive Hot Take's recorder on this Mac, and (with `hottake mcp`) the same controls as an
// MCP server over stdio. It only talks to the running app through a private socket in the user's own Library folder.

let version = "0.1.0"

let usage = """
hottake \(version): control Hot Take's recorder from an agent. Turn on Settings > Recording > "Let local agents control recording" first.

  hottake status                     what the recorder is doing
  hottake displays                   every display: number, name, position and size (the position clicks are aimed with)
  hottake screenshot [--display N] [--width PX]
                                     a picture of a screen, without recording; prints the PNG's path
  hottake preflight [--display N] [--term WORD]...
                                     before recording: which apps are on that screen, and whether sensitive text shows
  hottake window [--display N]       put Hot Take's window on a display
  hottake start [--display N]        start recording a screen (after the usual countdown); N counts from 1
  hottake marker NAME [--back SECONDS]
                                     name this moment (while recording); markers become chapters and anchors for edits
  hottake retake NAME                a step went wrong and you are redoing it: the edit cuts the failed attempt
  hottake pause | resume | stop      stop saves the take and prints its file and markers
  hottake markers [--take NAME]      the markers of a take (the live ones while recording)
  hottake edit [--take NAME] [--replace] FILE|-
                                     apply an edit list (JSON; "-" reads stdin) to the take's Studio draft
  hottake render [--take NAME] [--no-chapters]
                                     save the edited take as a new copy in the library
  hottake frames [--take NAME] [--at S,S,...] [--scan] [--term WORD]...
                                     pictures from a video (the last saved copy by default) and one contact sheet, to check an
                                     edit; --scan also looks for sensitive text in them
  hottake discard --take NAME        move a take an agent recorded (or a copy it saved) to the Trash
  hottake mcp                        speak the Model Context Protocol on stdin/stdout

Mouse and keyboard (only after the person turns on "Also let agents use the mouse and keyboard" in Hot Take's Settings):
  hottake move X Y [--display N]     glide the pointer there
  hottake click X Y [--display N] [--double]
  hottake drag X1 Y1 X2 Y2 [--display N]
  hottake key SPEC                   a key or combination: return, escape, tab, space, left, cmd+shift+s
  hottake type TEXT                  type text as it is
  With --display, X and Y are points from that display's top-left; without it, they are desktop points (see hottake displays).
  Careful: while you record, ⌘N does nothing to a take you started, but other shortcuts reach whatever app is in front.

Answers are JSON. The exit status is 0 on success, 1 when Hot Take refused, 2 when it could not be reached.
"""

func printErr(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }

enum ClientError: Error { case unreachable(String) }

/// Sends one request and waits for its answer. A stop or render can take a while (captions are made first), so there is no timeout.
func send(_ request: AgentRequest) throws -> AgentResponse {
    let url = AgentPaths.socket()
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw ClientError.unreachable("Could not open a socket.") }
    defer { close(fd) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    guard AgentPaths.isUsable(socket: url) else { throw ClientError.unreachable("The socket path is too long.") }
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        for (index, byte) in url.path.utf8.enumerated() { buffer[index] = byte }
    }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard connected == 0 else {
        throw ClientError.unreachable(
            "Could not reach Hot Take. Open the app and turn on Settings > Recording > \"Let local agents control recording\".")
    }
    let payload = AgentWire.encode(request)
    var sent = 0
    let ok = payload.withUnsafeBytes { raw -> Bool in
        while sent < payload.count {
            let count = write(fd, raw.baseAddress!.advanced(by: sent), payload.count - sent)
            if count <= 0 { return false }
            sent += count
        }
        return true
    }
    guard ok else { throw ClientError.unreachable("Hot Take closed the connection.") }
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 8192)
    while true {
        if let line = AgentWire.nextLine(in: &buffer) {
            do { return try AgentWire.decodeResponse(line) } catch { throw ClientError.unreachable("Hot Take sent something unreadable.") }
        }
        let count = read(fd, &chunk, chunk.count)
        if count <= 0 { throw ClientError.unreachable("Hot Take closed the connection before answering.") }
        buffer.append(chunk, count: count)
    }
}

func pretty(_ response: AgentResponse) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: (try? encoder.encode(response)) ?? Data(), as: UTF8.self)
}

/// Pulls `--name value` out of the arguments.
func option(_ name: String, in args: inout [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    let value = args[index + 1]
    args.removeSubrange(index...(index + 1))
    return value
}

/// Pulls every `--name value` out of the arguments (for options that can be repeated).
func options(_ name: String, in args: inout [String]) -> [String] {
    var values: [String] = []
    while let value = option(name, in: &args) { values.append(value) }
    return values
}

func flag(_ name: String, in args: inout [String]) -> Bool {
    guard let index = args.firstIndex(of: name) else { return false }
    args.remove(at: index)
    return true
}

/// `move`, `click`, `drag`, `key` and `type`: real input, if the person has allowed it.
func runInput(_ command: String, _ arguments: [String]) -> Int32 {
    var args = arguments
    var display: Int?
    if let text = option("--display", in: &args) {
        guard let number = Int(text), number >= 1 else { printErr("--display needs a number from 1."); return 2 }
        display = number
    }
    let double = flag("--double", in: &args)
    func numbers(_ count: Int) -> [Double]? {
        let values = args.compactMap(Double.init)
        return args.count == count && values.count == count ? values : nil
    }
    let action: InputAction
    switch command {
    case "move":
        guard let n = numbers(2) else { printErr("move needs X and Y."); return 2 }
        action = .move(x: n[0], y: n[1], display: display)
    case "click":
        guard let n = numbers(2) else { printErr("click needs X and Y."); return 2 }
        action = .click(x: n[0], y: n[1], display: display, double: double)
    case "drag":
        guard let n = numbers(4) else { printErr("drag needs X1 Y1 X2 Y2."); return 2 }
        action = .drag(x1: n[0], y1: n[1], x2: n[2], y2: n[3], display: display)
    case "key":
        guard args.count == 1 else { printErr("key needs one key or combination, like return or cmd+shift+s."); return 2 }
        action = .key(args[0])
    default:
        guard !args.isEmpty else { printErr("type needs the text to type."); return 2 }
        action = .type(args.joined(separator: " "))
    }
    let response = performInput(action, send: send)
    print(pretty(response))
    return response.ok ? 0 : (response.error?.contains("Could not reach") == true ? 2 : 1)
}

func run(_ arguments: [String]) -> Int32 {
    var args = arguments
    guard let command = args.first else { print(usage); return 0 }
    args.removeFirst()
    if ["help", "-h", "--help"].contains(command) { print(usage); return 0 }
    if command == "--version" { print(version); return 0 }
    if command == "mcp" { MCPServer().run(); return 0 }

    var request = AgentRequest(command: command)
    switch command {
    case "move", "click", "drag", "key", "type":
        return runInput(command, args)
    case "status", "ping", "stop", "pause", "resume", "displays":
        break
    case "screenshot", "preflight", "window":
        if let text = option("--display", in: &args) {
            guard let number = Int(text), number >= 1 else { printErr("--display needs a number from 1."); return 2 }
            request.display = number
        }
        if command == "screenshot", let text = option("--width", in: &args) {
            guard let width = Int(text), width >= 200 else { printErr("--width needs a number of pixels, at least 200."); return 2 }
            request.width = width
        }
        if command == "preflight" { request.terms = options("--term", in: &args) }
    case "retake":
        let name = args.joined(separator: " ")
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { printErr("retake needs the name of the step you are redoing."); return 2 }
        request.command = "marker"
        request.name = "\(AgentRetakes.prefix) \(name)"
    case "frames":
        request.take = option("--take", in: &args)
        request.scan = flag("--scan", in: &args) ? true : nil
        let terms = options("--term", in: &args)
        request.terms = terms.isEmpty ? nil : terms
        if let text = option("--at", in: &args) {
            let times = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard !times.isEmpty, times.count == text.split(separator: ",").count else { printErr("--at needs seconds separated by commas, like 3,10.5,40."); return 2 }
            request.times = times
        }
    case "discard":
        guard let name = option("--take", in: &args), !name.isEmpty else { printErr("discard needs --take NAME."); return 2 }
        request.take = name
    case "start":
        if let text = option("--display", in: &args) {
            guard let number = Int(text), number >= 1 else { printErr("--display needs a number from 1."); return 2 }
            request.display = number
        }
    case "marker":
        if let text = option("--back", in: &args) {
            guard let seconds = Double(text), seconds >= 0 else { printErr("--back needs a number of seconds."); return 2 }
            request.back = seconds
        }
        let name = args.joined(separator: " ")
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { printErr("marker needs a name."); return 2 }
        request.name = name
    case "markers":
        request.take = option("--take", in: &args)
    case "edit":
        request.take = option("--take", in: &args)
        let replace = flag("--replace", in: &args)
        guard let path = args.first else { printErr("edit needs a file of JSON, or - for stdin."); return 2 }
        let data = path == "-" ? FileHandle.standardInput.readDataToEndOfFile() : (try? Data(contentsOf: URL(fileURLWithPath: path)))
        guard let data else { printErr("Could not read \(path)."); return 2 }
        do {
            var list = try JSONDecoder().decode(EditList.self, from: data)
            if replace { list.replace = true }
            request.edit = list
        } catch {
            printErr("That is not a valid edit list: \(error)")
            return 2
        }
    case "render":
        request.take = option("--take", in: &args)
        if flag("--no-chapters", in: &args) { request.edit = EditList(chapters: false) }
    default:
        printErr("Unknown command “\(command)”.\n\n" + usage)
        return 2
    }
    do {
        let response = try send(request)
        print(pretty(response))
        return response.ok ? 0 : 1
    } catch ClientError.unreachable(let message) {
        printErr(message)
        return 2
    } catch {
        printErr("\(error)")
        return 2
    }
}

exit(run(Array(CommandLine.arguments.dropFirst())))
