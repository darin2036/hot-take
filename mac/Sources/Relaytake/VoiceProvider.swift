import Foundation
import RelaytakeCore

/// Which voice speaks a voiceover, and whether it is ready: the voice on this Mac (Kokoro) or one on the person's ElevenLabs account.
/// The Studio and agent edits both go through here, so they follow the same choice in Settings ▸ Voice.
@MainActor
enum VoiceProvider {
    enum Source: String, CaseIterable, Identifiable {
        case local, elevenLabs
        var id: String { rawValue }
        var title: String { self == .local ? "On this Mac" : "ElevenLabs" }
        /// Whether speaking sends the words of the lines off this Mac.
        var sendsText: Bool { self == .elevenLabs }
    }

    struct Problem: Error { let message: String }

    /// A voice ready to speak.
    struct Ready {
        let engine: SpeechEngine
        let source: Source
        let name: String
        /// Said when the voice an agent asked for was not available and another was used.
        let note: String?
        /// "Heart on this Mac" or "Rachel on ElevenLabs"
        var label: String { source == .local ? "\(name) on this Mac" : "\(name) on ElevenLabs" }
    }

    /// What Settings says the person wants: this Mac unless they chose ElevenLabs.
    static var source: Source { Source(rawValue: UserDefaults.standard.string(forKey: Pref.voiceSource) ?? "") ?? .local }

    /// A look at the current choice without preparing anything, for the Studio to describe before it speaks.
    struct Status {
        let source: Source
        /// The voice's name once it can be used, else nil.
        let voice: String?
        /// What to do first, when it cannot be used yet.
        let setup: String?
    }

    static func status() -> Status {
        switch source {
        case .local:
            let store = LocalVoiceStore.shared
            return store.isReady
                ? Status(source: .local, voice: store.voice.name, setup: nil)
                : Status(source: .local, voice: nil, setup: "Download the voice on this Mac in Settings ▸ Voice first.")
        case .elevenLabs:
            let account = ElevenLabsAccount.shared
            return account.signedIn && !account.voiceName.isEmpty
                ? Status(source: .elevenLabs, voice: account.voiceName, setup: nil)
                : Status(source: .elevenLabs, voice: nil, setup: "Sign in to ElevenLabs and choose a voice in Settings ▸ Voice first.")
        }
    }

    /// Whether a local agent may speak with `source`. The voice on this Mac costs nothing and sends nothing, so agent control being on is
    /// enough; ElevenLabs spends the person's characters, so it also needs its own switch.
    static func agentsMay(use source: Source) -> Bool {
        source == .local || ElevenLabsAccount.agentsAllowed
    }

    /// An engine for `source` (the person's choice if nil) and the voice named, else the voice chosen in Settings.
    static func ready(source wanted: Source? = nil, voice named: String? = nil) async -> Result<Ready, Problem> {
        let source = wanted ?? Self.source
        let asked = named?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        switch source {
        case .local:
            let store = LocalVoiceStore.shared
            store.refresh()
            guard store.isReady else {
                return .failure(Problem(message: "the voice on this Mac has not been downloaded (Settings ▸ Voice)"))
            }
            let found = KokoroModel.voice(named: asked)
            let voice = found ?? store.voice
            let note = asked != nil && found == nil
                ? "There is no on-device voice “\(asked!)”, so “\(voice.name)”, the one chosen in Settings, was used. The choices are \(KokoroModel.voices.map(\.name).joined(separator: ", "))."
                : nil
            guard let engine = store.engine(voice: voice) else { return .failure(Problem(message: "the voice on this Mac is not ready")) }
            return .success(Ready(engine: engine, source: .local, name: voice.name, note: note))
        case .elevenLabs:
            let account = ElevenLabsAccount.shared
            guard account.signedIn else { return .failure(Problem(message: "you have not signed in to ElevenLabs (Settings ▸ Voice)")) }
            if account.voices.isEmpty { await account.refresh() }
            guard let voice = account.voice(named: asked), let engine = account.engine(voice: voice) else {
                return .failure(Problem(message: "no ElevenLabs voice is chosen (Settings ▸ Voice)"))
            }
            let note = asked != nil && voice.id != asked && voice.name.caseInsensitiveCompare(asked!) != .orderedSame
                ? "There is no voice “\(asked!)” on the account, so “\(voice.name)”, the one chosen in Settings, was used."
                : nil
            return .success(Ready(engine: engine, source: .elevenLabs, name: voice.name, note: note))
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
