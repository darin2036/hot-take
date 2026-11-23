import AVFoundation
import Foundation
import PlainspokenSpeech
import RelaytakeCore
import Security
import SwiftUI

// The person's ElevenLabs account, as far as Hot Take needs it: an API key kept in the Keychain, the voices on the account and what
// is left of the plan. ElevenLabs has no browser sign-in for other apps, so "signing in" is pasting a key. Nothing here runs until the
// person signs in or asks for a voiceover; the app otherwise refuses every web request (see `NetworkGuard`).

/// The key lives in the Keychain, on this Mac only, readable only while it is unlocked. It is never written to preferences, a take,
/// a log, or anything an agent can read.
enum VoiceKeychain {
    private static let service = "org.relaytake.mac.elevenlabs"
    private static let account = "api-key"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}

/// The only code that reaches the network for a voice. It will only talk to ElevenLabs over HTTPS, with no cookies and no cache,
/// and it opens the app's network guard for just the length of one request.
struct ElevenLabsNetwork: ElevenLabsTransport {
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        guard request.url?.scheme == "https", request.url?.host == ElevenLabs.host else {
            throw ElevenLabs.Failure.offline("Hot Take only talks to \(ElevenLabs.host).")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 90
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        return try await NetworkGuard.allowing {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }
}

@MainActor
final class ElevenLabsAccount: ObservableObject {
    static let shared = ElevenLabsAccount()

    @Published private(set) var signedIn = VoiceKeychain.read() != nil
    @Published private(set) var voices: [ElevenLabs.Voice] = []
    @Published private(set) var subscription: ElevenLabs.Subscription?
    @Published private(set) var busy = false
    /// What went wrong with the last sign-in or refresh, in words for the person.
    @Published private(set) var problem: String?

    let service = ElevenLabsService(transport: ElevenLabsNetwork())

    private var defaults: UserDefaults { .standard }

    var voiceID: String { defaults.string(forKey: Pref.elevenLabsVoice) ?? "" }
    var voiceName: String { defaults.string(forKey: Pref.elevenLabsVoiceName) ?? "" }
    var model: ElevenLabs.Model { ElevenLabs.Model.named(defaults.string(forKey: Pref.elevenLabsModel)) }
    /// Whether a local agent may spend this account's characters. Off unless the person turns it on.
    static var agentsAllowed: Bool { UserDefaults.standard.bool(forKey: Pref.elevenLabsAgents) }

    func choose(_ voice: ElevenLabs.Voice) {
        defaults.set(voice.id, forKey: Pref.elevenLabsVoice)
        defaults.set(voice.name, forKey: Pref.elevenLabsVoiceName)
        objectWillChange.send()
    }

    /// Checks the pasted key with ElevenLabs and keeps it only if it works.
    func signIn(pasted: String) async {
        busy = true
        problem = nil
        defer { busy = false }
        do {
            let result = try await service.signIn(key: pasted)
            guard VoiceKeychain.save(result.key) else {
                problem = "The key worked, but the Keychain would not keep it."
                return
            }
            signedIn = true
            adopt(voices: result.voices)
            subscription = result.subscription
        } catch {
            problem = error.localizedDescription
        }
    }

    func signOut() {
        VoiceKeychain.delete()
        signedIn = false
        voices = []
        subscription = nil
        problem = nil
        defaults.removeObject(forKey: Pref.elevenLabsVoice)
        defaults.removeObject(forKey: Pref.elevenLabsVoiceName)
        defaults.set(false, forKey: Pref.elevenLabsAgents)
    }

    /// Reloads the voices and the plan, for when Settings opens or an agent names a voice.
    func refresh() async {
        guard let key = VoiceKeychain.read() else { signedIn = false; return }
        busy = true
        defer { busy = false }
        do {
            adopt(voices: try await service.voices(key: key))
            subscription = try? await service.subscription(key: key)
            problem = nil
        } catch ElevenLabs.Failure.invalidKey {
            // The key was revoked or replaced in the account: keep nothing that no longer works.
            signOut()
            problem = ElevenLabs.Failure.invalidKey.localizedDescription
        } catch {
            problem = error.localizedDescription
        }
    }

    private func adopt(voices list: [ElevenLabs.Voice]) {
        voices = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !voices.contains(where: { $0.id == voiceID }), let first = voices.first { choose(first) }
    }

    /// The voice an agent named (by name or id), else the one the person chose.
    func voice(named name: String?) -> ElevenLabs.Voice? {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
           let match = voices.first(where: { $0.id == name || $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        return voices.first { $0.id == voiceID }
    }

    /// An engine for `voice` with the key from the Keychain, or nil when signed out.
    func engine(voice: ElevenLabs.Voice) -> ElevenLabsEngine? {
        guard let key = VoiceKeychain.read() else { return nil }
        return ElevenLabsEngine(service: service, key: key, voiceID: voice.id, model: model)
    }
}

/// Speaks lines and keeps the audio beside the take, where the Studio draft and a shared copy find it again.
enum VoiceGeneration {
    static func run(
        lines: [VoiceLine], engine: SpeechEngine, files: TakeFiles, progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> VoiceoverPlan.Generation {
        let first = VoiceoverPlan.freeAudioNumber(in: files)
        let ext = engine.fileExtension
        do {
            defer { Task { await engine.finish() } }
            return try await VoiceoverPlan.generate(
                lines: lines, engine: engine,
                destination: { files.audioFile(number: first + $0, extension: ext) },
                measure: { url in
                    guard let seconds = try? await AVURLAsset(url: url).load(.duration).seconds, seconds.isFinite else { return nil }
                    return seconds
                },
                progress: progress)
        } catch {
            // Cancelled: nothing will use the audio made so far, so it is not left behind in the take's folder.
            for index in lines.indices { try? FileManager.default.removeItem(at: files.audioFile(number: first + index, extension: ext)) }
            throw error
        }
    }
}
