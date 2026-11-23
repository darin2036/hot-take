import Foundation

// A voice for a voiceover, made by the person's own ElevenLabs account. ElevenLabs has no browser sign-in for other apps, so
// "signing in" is pasting an API key from the account (the app keeps it in the Keychain). Only the lines to be spoken are sent, only
// to api.elevenlabs.io, and only when the person (or an agent they have allowed) asks for a voiceover.
//
// Nothing in this file sends anything. It builds requests, reads replies, plans which line goes where on the edited video and
// how fast it must be spoken to fit, and lays the finished audio on the Voiceover track. The app supplies the transport that
// actually reaches the network, so every rule here is tested without one.

public enum ElevenLabs {
    public static let host = "api.elevenlabs.io"
    /// Where a person makes a key in their account.
    public static let keysPage = URL(string: "https://elevenlabs.io/app/settings/api-keys")!
    /// ElevenLabs accepts a speaking speed between these (1 is normal).
    public static let speedRange = 0.7...1.2
    /// Most characters an agent may spend in one request. The text is billed to the person's own ElevenLabs plan.
    public static let agentCharacterLimit = 5_000
    /// The name given to clips made here, so a second run replaces the first instead of stacking on it.
    public static let clipName = "ElevenLabs voice"
    /// A line longer than this is not sent (the service has its own, larger limit).
    public static let lineCharacterLimit = 2_500

    /// A speech model. Both keep the voice's own settings and honour a speaking speed, which is how a line is fitted to its part.
    public struct Model: Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let detail: String

        public static let multilingualV2 = Model(
            id: "eleven_multilingual_v2", title: "Multilingual v2", detail: "Natural and expressive in many languages. Uses one credit per character.")
        public static let flashV2_5 = Model(
            id: "eleven_flash_v2_5", title: "Flash v2.5", detail: "Faster and cheaper, a little less expressive. Uses half a credit per character.")
        public static let all = [multilingualV2, flashV2_5]

        /// The model with this id, else the default.
        public static func named(_ id: String?) -> Model { all.first { $0.id == id } ?? multilingualV2 }
    }

    public struct Voice: Equatable, Identifiable, Codable, Sendable {
        public let id: String
        public let name: String
        /// "premade", "cloned", "professional" and so on, as the service names it.
        public let category: String?

        public init(id: String, name: String, category: String? = nil) {
            self.id = id; self.name = name; self.category = category
        }
    }

    public struct Subscription: Equatable, Sendable {
        public var used: Int
        public var limit: Int
        public var resets: Date?
        public var remaining: Int { max(0, limit - used) }

        public init(used: Int, limit: Int, resets: Date? = nil) {
            self.used = used; self.limit = limit; self.resets = resets
        }
    }

    /// Why a request did not work, in words a person can act on.
    public enum Failure: Error, Equatable, LocalizedError, Sendable {
        case invalidKey
        case missingPermission(String)
        case outOfCharacters
        case rateLimited
        case voiceNotFound
        case rejected(String)
        case server(Int)
        case offline(String)
        case unreadable

        public var errorDescription: String? {
            switch self {
            case .invalidKey: "ElevenLabs did not accept that key. Make a new one in your ElevenLabs account and paste it again."
            case .missingPermission(let what): "The key is missing a permission it needs (\(what)). Turn it on for the key in your ElevenLabs account, or make a new key."
            case .outOfCharacters: "Your ElevenLabs plan has no characters left this period."
            case .rateLimited: "ElevenLabs asked Hot Take to slow down. Try again in a moment."
            case .voiceNotFound: "That voice is not in your ElevenLabs account any more. Choose another in Settings."
            case .rejected(let why): "ElevenLabs could not speak that: \(why)"
            case .server(let code): "ElevenLabs had a problem (\(code)). Try again later."
            case .offline(let why): "Could not reach ElevenLabs: \(why)"
            case .unreadable: "ElevenLabs sent back something Hot Take could not read."
            }
        }
    }

    // MARK: Requests

    /// A voice id is letters, digits, dashes and underscores. Anything else would change which address is asked.
    public static func isSafeVoiceID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// A key is one run of printable ASCII. Anything else (a space, a newline) cannot be a key and must never reach a header.
    public static func cleaned(key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8, trimmed.count <= 200,
              trimmed.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 32 && $0.value < 127 })
        else { return nil }
        return trimmed
    }

    private static func request(_ path: String, query: [URLQueryItem] = [], method: String, key: String) -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!, timeoutInterval: 90)
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    public static func voicesRequest(key: String, pageToken: String? = nil) -> URLRequest {
        var query = [URLQueryItem(name: "page_size", value: "100")]
        if let pageToken { query.append(URLQueryItem(name: "next_page_token", value: pageToken)) }
        var request = request("/v2/voices", query: query, method: "GET", key: key)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public static func subscriptionRequest(key: String) -> URLRequest {
        var request = request("/v1/user/subscription", method: "GET", key: key)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Speech for `text`. `speed` is left out at 1 so the voice keeps the settings saved in the account.
    public static func speechRequest(
        text: String, voiceID: String, model: Model, speed: Double = 1, previousText: String? = nil, nextText: String? = nil, key: String
    ) -> URLRequest? {
        guard isSafeVoiceID(voiceID) else { return nil }
        var request = request(
            "/v1/text-to-speech/\(voiceID)", query: [URLQueryItem(name: "output_format", value: "mp3_44100_128")], method: "POST", key: key)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        var body: [String: Any] = ["text": text, "model_id": model.id]
        if abs(speed - 1) > 0.001 {
            body["voice_settings"] = ["speed": min(speedRange.upperBound, max(speedRange.lowerBound, speed))]
        }
        if let previousText, !previousText.isEmpty { body["previous_text"] = previousText }
        if let nextText, !nextText.isEmpty { body["next_text"] = nextText }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    // MARK: Replies

    public static func parseVoices(_ data: Data) -> (voices: [Voice], next: String?)? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = object["voices"] as? [[String: Any]]
        else { return nil }
        let voices = list.compactMap { item -> Voice? in
            guard let id = item["voice_id"] as? String, let name = item["name"] as? String, isSafeVoiceID(id) else { return nil }
            return Voice(id: id, name: name, category: item["category"] as? String)
        }
        let more = object["has_more"] as? Bool ?? false
        return (voices, more ? object["next_page_token"] as? String : nil)
    }

    public static func parseSubscription(_ data: Data) -> Subscription? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let used = (object["character_count"] as? NSNumber)?.intValue,
              let limit = (object["character_limit"] as? NSNumber)?.intValue
        else { return nil }
        let resets = (object["next_character_count_reset_unix"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return Subscription(used: used, limit: limit, resets: resets)
    }

    /// The failure a non-success reply stands for. ElevenLabs puts the reason in `detail`, as text or as a status and message.
    public static func failure(status: Int, body: Data) -> Failure {
        var code = ""
        var message = ""
        if let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] {
            switch object["detail"] {
            case let text as String: message = text
            case let detail as [String: Any]:
                code = (detail["status"] as? String) ?? ""
                message = (detail["message"] as? String) ?? ""
            case let list as [[String: Any]]: message = (list.first?["msg"] as? String) ?? ""
            default: break
            }
        }
        switch code {
        case "quota_exceeded": return .outOfCharacters
        case "missing_permissions": return .missingPermission(permission(in: message))
        case "invalid_api_key": return .invalidKey
        case "voice_not_found": return .voiceNotFound
        default: break
        }
        switch status {
        case 401, 403: return .invalidKey
        case 404: return .voiceNotFound
        case 429: return .rateLimited
        case 400, 422: return .rejected(String(message.prefix(200)).isEmpty ? "it was refused" : String(message.prefix(200)))
        case 500...599: return .server(status)
        default: return .rejected("status \(status)")
        }
    }

    /// "…is missing the permission text_to_speech to execute…" → "Text to speech".
    static func permission(in message: String) -> String {
        let words = message.split(separator: " ")
        if let at = words.firstIndex(of: "permission"), at + 1 < words.count {
            let name = words[at + 1].trimmingCharacters(in: .punctuationCharacters).replacingOccurrences(of: "_", with: " ")
            if !name.isEmpty { return name.prefix(1).uppercased() + name.dropFirst() }
        }
        return "a permission"
    }
}

/// Sends one request and says what came back. The app's version reaches the network; tests supply their own.
public protocol ElevenLabsTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int)
}

public struct ElevenLabsService: Sendable {
    public let transport: ElevenLabsTransport

    public init(transport: ElevenLabsTransport) { self.transport = transport }

    private func send(_ request: URLRequest) async throws -> Data {
        let reply: (data: Data, status: Int)
        do { reply = try await transport.send(request) }
        catch let failure as ElevenLabs.Failure { throw failure }
        catch is CancellationError { throw CancellationError() }
        catch { throw ElevenLabs.Failure.offline(error.localizedDescription) }
        guard (200..<300).contains(reply.status) else { throw ElevenLabs.failure(status: reply.status, body: reply.data) }
        return reply.data
    }

    public func voices(key: String) async throws -> [ElevenLabs.Voice] {
        var all: [ElevenLabs.Voice] = []
        var token: String?
        for _ in 0..<5 {
            guard let page = ElevenLabs.parseVoices(try await send(ElevenLabs.voicesRequest(key: key, pageToken: token))) else {
                throw ElevenLabs.Failure.unreadable
            }
            all += page.voices
            guard let next = page.next else { break }
            token = next
        }
        return all
    }

    public func subscription(key: String) async throws -> ElevenLabs.Subscription {
        guard let value = ElevenLabs.parseSubscription(try await send(ElevenLabs.subscriptionRequest(key: key))) else {
            throw ElevenLabs.Failure.unreadable
        }
        return value
    }

    /// MP3 audio of `text`.
    public func speech(
        text: String, voiceID: String, model: ElevenLabs.Model, speed: Double, previousText: String?, nextText: String?, key: String
    ) async throws -> Data {
        guard let request = ElevenLabs.speechRequest(
            text: text, voiceID: voiceID, model: model, speed: speed, previousText: previousText, nextText: nextText, key: key)
        else { throw ElevenLabs.Failure.voiceNotFound }
        let data = try await send(request)
        guard data.count > 200 else { throw ElevenLabs.Failure.unreadable }
        return data
    }

    /// Checks a pasted key. The plan's remaining characters are shown when the key may read them; a key limited to speech and
    /// voices is accepted too, since that is all this app needs. A key that cannot list voices is refused: it could not be used.
    public func signIn(key pasted: String) async throws -> (key: String, subscription: ElevenLabs.Subscription?, voices: [ElevenLabs.Voice]) {
        guard let key = ElevenLabs.cleaned(key: pasted) else { throw ElevenLabs.Failure.invalidKey }
        let voices = try await voices(key: key)
        let subscription = try? await subscription(key: key)
        return (key, subscription, voices)
    }
}

// MARK: Speech engines

/// Why one line could not be spoken, in terms every engine shares.
public enum SpeechFailure: Error, Equatable, Sendable {
    /// This line was refused; the others can still be spoken.
    case lineRefused(String)
    /// The engine is busy; trying again shortly may work.
    case busy
    /// Nothing more can be spoken until something changes (a bad key, no characters left, a missing voice or model).
    case stop(String)
}

/// Something that turns a line of text into audio: a cloud voice, or a model that runs on this Mac.
public protocol SpeechEngine: Sendable {
    /// The audio's file extension: "mp3", "wav".
    var fileExtension: String { get }
    /// Whether it can speak faster or slower on request, which is how a line is fitted to its part of the video.
    var supportsSpeed: Bool { get }
    /// The speeds it may be asked for. A line is never sped up past the top of this, so it still sounds like speech.
    var speedRange: ClosedRange<Double> { get }
    /// Audio of `text`. `previous` and `next` are the neighbouring lines, so the voice can carry its tone across them.
    func speak(text: String, speed: Double, previous: String?, next: String?) async throws -> Data
    /// Called once when a voiceover is done, so an engine that holds memory can let it go.
    func finish() async
}

extension SpeechEngine {
    public var speedRange: ClosedRange<Double> { ElevenLabs.speedRange }
    public func finish() async {}
}

/// A voice from the person's own ElevenLabs account.
public struct ElevenLabsEngine: SpeechEngine {
    public let service: ElevenLabsService
    public let key: String
    public let voiceID: String
    public let model: ElevenLabs.Model

    public init(service: ElevenLabsService, key: String, voiceID: String, model: ElevenLabs.Model) {
        self.service = service; self.key = key; self.voiceID = voiceID; self.model = model
    }

    public var fileExtension: String { "mp3" }
    public var supportsSpeed: Bool { true }

    public func speak(text: String, speed: Double, previous: String?, next: String?) async throws -> Data {
        do {
            return try await service.speech(
                text: text, voiceID: voiceID, model: model, speed: speed, previousText: previous, nextText: next, key: key)
        } catch let failure as ElevenLabs.Failure {
            switch failure {
            case .rejected(let why): throw SpeechFailure.lineRefused(why)
            case .rateLimited: throw SpeechFailure.busy
            default: throw SpeechFailure.stop(failure.localizedDescription)
            }
        }
    }
}

// MARK: Planning a voiceover

/// One line to speak and where it goes on the *edited* video.
public struct VoiceLine: Equatable, Sendable {
    public var name: String
    public var text: String
    /// Edited-video seconds where the line begins.
    public var start: Double
    /// Seconds the line may take before it runs into the next one.
    public var room: Double

    public init(name: String, text: String, start: Double, room: Double) {
        self.name = name; self.text = text; self.start = start; self.room = room
    }
}

public enum VoiceoverPlan {
    /// Silence kept after a line, so the next one does not follow without a breath.
    public static let gap = 0.15

    /// The lines of an agent's narration: each beat's text begins just inside the beat and may take the rest of it.
    public static func lines(beats: [NarrationBeat]) -> [VoiceLine] {
        beats.compactMap { beat in
            let text = beat.text?.split(whereSeparator: \.isWhitespace).joined(separator: " ") ?? ""
            guard !text.isEmpty, beat.length > 0.3 else { return nil }
            let start = beat.start + min(0.1, beat.length * 0.05)
            return VoiceLine(name: beat.name, text: text, start: start, room: max(0.3, beat.end - start - gap))
        }
    }

    /// The lines of a transcript (captured at times in the original), moved onto the edited video. A line the edit cut away is dropped;
    /// each may take the time until the next begins, and the last, until the video ends.
    public static func lines(transcript: [CaptionSegment], cuts: EditModel, outputDuration: Double) -> [VoiceLine] {
        var found: [(start: Double, text: String)] = []
        for cue in transcript {
            let text = cue.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !text.isEmpty else { continue }
            let spans = cuts.outputSpans(forSource: TimeSpan(start: cue.start, end: cue.end))
            guard let first = spans.first, let last = spans.last, last.end - first.start >= 0.3 else { continue }
            found.append((first.start, text))
        }
        found.sort { $0.start < $1.start }
        return found.enumerated().map { index, item in
            let next = index + 1 < found.count ? found[index + 1].start : outputDuration
            return VoiceLine(name: "Line \(index + 1)", text: item.text, start: item.start, room: max(0.3, next - item.start - gap))
        }
    }

    /// Characters the service will bill for.
    public static func characters(_ lines: [VoiceLine]) -> Int { lines.reduce(0) { $0 + $1.text.count } }

    /// The speed that makes audio lasting `duration` fit in `room`, or nil if it already fits. Never above what the service allows,
    /// so a line that is still too long is reported, not squashed into nonsense.
    public static func speed(for duration: Double, room: Double, maximum: Double = ElevenLabs.speedRange.upperBound) -> Double? {
        guard room > 0, duration > room + 0.05 else { return nil }
        return min(maximum, (duration / room * 1.03 * 100).rounded(.up) / 100)
    }

    public struct Spoken: Equatable, Sendable {
        public var line: VoiceLine
        public var url: URL
        public var duration: Double
        public var speed: Double
        /// Still longer than its room at the fastest speed allowed.
        public var overran: Bool
    }

    public struct Generation: Sendable {
        public var spoken: [Spoken] = []
        /// Lines not sent, and why.
        public var skipped: [String] = []
        /// What ended the run early. Whatever was made before it is kept: it may have been paid for.
        public var stopped: String?
        public var charactersSent = 0
    }

    /// Speaks each line in turn with `engine`, writing `destination(index)` and measuring it with `measure`. A line that comes out too
    /// long for its room is spoken again, faster (if the engine can). Stops at the first failure that would repeat for every line (a bad
    /// key, no characters left, a missing voice); one line the engine refuses is skipped and the rest go on. Throws only when cancelled.
    public static func generate(
        lines: [VoiceLine], engine: SpeechEngine, retryDelay: Double = 2, destination: (Int) -> URL, measure: (URL) async -> Double?,
        progress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> Generation {
        var result = Generation()
        for (index, line) in lines.enumerated() {
            try Task.checkCancellation()
            progress(index, lines.count)
            guard line.text.count <= ElevenLabs.lineCharacterLimit else {
                result.skipped.append("“\(line.name)” is too long to send (\(line.text.count) characters). Split it into shorter lines.")
                continue
            }
            let previous = index > 0 ? String(lines[index - 1].text.suffix(200)) : nil
            let next = index + 1 < lines.count ? String(lines[index + 1].text.prefix(200)) : nil
            let url = destination(index)
            do {
                var speed = 1.0
                var duration = 0.0
                for attempt in 0..<2 {
                    let data = try await speak(line, engine: engine, speed: speed, previous: previous, next: next, retryDelay: retryDelay)
                    result.charactersSent += line.text.count
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url, options: .atomic)
                    guard let measured = await measure(url), measured > 0.1 else { throw SpeechFailure.stop("The audio could not be read back.") }
                    duration = measured
                    guard attempt == 0, engine.supportsSpeed, let faster = self.speed(for: measured, room: line.room, maximum: engine.speedRange.upperBound), faster > speed
                    else { break }
                    speed = faster
                }
                result.spoken.append(Spoken(line: line, url: url, duration: duration, speed: speed, overran: duration > line.room + 0.05))
            } catch is CancellationError {
                throw CancellationError()
            } catch SpeechFailure.lineRefused(let why) {
                result.skipped.append("“\(line.name)” was refused: \(why)")
            } catch SpeechFailure.busy {
                result.stopped = "The voice service kept asking Hot Take to slow down. Try again in a moment."
                progress(lines.count, lines.count)
                return result
            } catch SpeechFailure.stop(let why) {
                result.stopped = why
                progress(lines.count, lines.count)
                return result
            } catch {
                result.stopped = error.localizedDescription
                return result
            }
        }
        progress(lines.count, lines.count)
        return result
    }

    private static func speak(
        _ line: VoiceLine, engine: SpeechEngine, speed: Double, previous: String?, next: String?, retryDelay: Double
    ) async throws -> Data {
        var tries = 0
        while true {
            do {
                return try await engine.speak(text: line.text, speed: speed, previous: previous, next: next)
            } catch SpeechFailure.busy where tries < 2 {
                tries += 1
                try await Task.sleep(for: .seconds(retryDelay * Double(tries)))
            }
        }
    }

    /// Lays the spoken lines on the Voiceover track, replacing an earlier run of this voice, and optionally silences the recording's
    /// own sound. A line too long for its room is cut at the room's end with a short fade so it never talks over the next.
    public static func place(_ spoken: [Spoken], in project: inout StudioProject, replacingOriginalAudio: Bool) {
        guard !spoken.isEmpty else { return }
        project.clips.removeAll { $0.kind == .voiceover && $0.name == ElevenLabs.clipName }
        for item in spoken.sorted(by: { $0.line.start < $1.line.start }) {
            let id = project.addVoiceover(url: item.url, name: ElevenLabs.clipName, fileDuration: item.duration, start: item.line.start)
            if item.overran {
                project.updateClip(id) {
                    $0.length = item.line.room
                    $0.fadeOut = 0.15
                }
            }
        }
        if replacingOriginalAudio { project.originalVolume = 0 }
    }

    /// A short note per line that did not fit, for the person or the agent to act on.
    public static func warnings(for generation: Generation) -> [String] {
        var notes = generation.skipped
        for item in generation.spoken where item.overran {
            notes.append("“\(item.line.name)” is longer than its part of the video even at the fastest speed, so it was cut off. Shorten the line or lengthen the part.")
        }
        if let stopped = generation.stopped {
            notes.append("Voiceover stopped after \(generation.spoken.count) line\(generation.spoken.count == 1 ? "" : "s"): \(stopped)")
        }
        return notes
    }

    /// The next free file number in a take's audio folder for a name ending in `.N.<extension>`.
    public static func freeAudioNumber(in files: TakeFiles, fileManager: FileManager = .default) -> Int {
        let taken = Set(files.audioFiles(fileManager: fileManager).compactMap { url -> Int? in
            let parts = url.deletingPathExtension().lastPathComponent.split(separator: ".")
            return parts.last.flatMap { Int($0) }
        })
        return (1...).first { !taken.contains($0) } ?? 1
    }
}
