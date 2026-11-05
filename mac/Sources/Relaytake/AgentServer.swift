import Darwin
import Foundation
import OSLog
import RelaytakeCore

// The local door an agent knocks on. It exists only while Settings ▸ Recording ▸ "Let local agents control recording" is on,
// listens on a Unix socket inside the user's own Library folder (mode 0600, in a 0700 folder), and answers only the same
// user's processes. It is not a network port: nothing off this Mac can reach it, and nothing is sent anywhere.

final class AgentServer: @unchecked Sendable {
    static let shared = AgentServer()

    private let queue = DispatchQueue(label: "org.relaytake.mac.agent-server")
    private let log = Logger(subsystem: "org.relaytake.mac", category: "agent")
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?
    private weak var model: RecorderModel?

    /// Whether the person has let local agents in.
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: Pref.agentControl) }

    /// Whether the person also let agents use the mouse and keyboard (a second switch, off until they turn it on).
    static var inputAllowed: Bool { isEnabled && UserDefaults.standard.bool(forKey: Pref.agentInput) }

    /// Starts or stops the listener to match the setting. Safe to call whenever the setting may have changed.
    @MainActor
    func refresh(model: RecorderModel? = nil) {
        if let model { self.model = model }
        queue.sync { Self.isEnabled ? startLocked() : stopLocked() }
        if !Self.isEnabled { self.model?.agentWasTurnedOff() }
    }

    /// Closes the socket and removes its file, for when the app quits.
    func shutdown() { queue.sync { stopLocked() } }

    private func startLocked() {
        guard listener < 0 else { return }
        let socketURL = AgentPaths.socket()
        guard AgentPaths.isUsable(socket: socketURL) else {
            log.error("agent socket path is too long")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            log.error("could not create the agent folder: \(error.localizedDescription, privacy: .public)")
            return
        }
        unlink(socketURL.path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = socketURL.path
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in path.utf8.enumerated() { buffer[index] = byte }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { close(fd); log.error("could not bind the agent socket"); return }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else { close(fd); unlink(path); return }
        listener = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept() }
        source.resume()
        self.source = source
    }

    private func stopLocked() {
        source?.cancel()
        source = nil
        if listener >= 0 {
            close(listener)
            listener = -1
            unlink(AgentPaths.socket().path)
        }
    }

    private func accept() {
        let client = Darwin.accept(listener, nil, nil)
        guard client >= 0 else { return }
        var one: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        // Only this user's own processes are answered.
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == geteuid() else { close(client); return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.serve(client) }
    }

    /// One connection: a line in, a line out, until the other side hangs up.
    private func serve(_ client: Int32) {
        defer { close(client) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            while let line = AgentWire.nextLine(in: &buffer) {
                guard !line.isEmpty else { continue }
                let response = answer(line)
                if !Self.write(AgentWire.encode(response), to: client) { return }
            }
            let count = read(client, &chunk, chunk.count)
            if count <= 0 { return }
            buffer.append(chunk, count: count)
            if buffer.count > AgentWire.maximumLine {
                _ = Self.write(AgentWire.encode(AgentResponse.failure("That request is too large.")), to: client)
                return
            }
        }
    }

    private func answer(_ line: Data) -> AgentResponse {
        guard Self.isEnabled else { return .failure("Local agent control is turned off in Hot Take's Settings.") }
        let request: AgentRequest
        do { request = try AgentWire.decodeRequest(line) } catch {
            return .failure("That was not a valid request: \(error.localizedDescription)")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var response = AgentResponse.failure("Hot Take did not answer.")
        Task { @MainActor [weak self] in
            if let model = self?.model { response = await model.handleAgent(request) }
            semaphore.signal()
        }
        semaphore.wait()
        return response
    }

    private static func write(_ data: Data, to fd: Int32) -> Bool {
        var sent = 0
        return data.withUnsafeBytes { raw -> Bool in
            while sent < data.count {
                let count = Darwin.write(fd, raw.baseAddress!.advanced(by: sent), data.count - sent)
                if count <= 0 { return false }
                sent += count
            }
            return true
        }
    }
}
