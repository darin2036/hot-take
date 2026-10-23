import Foundation
import PlainspokenSpeech
import RelaytakeCore

/// What Settings says about recognizing speech: the engine, the language, and the custom vocabulary.
enum SpeechPreferences {
    static let engineKey = "speechEngine"
    static let localeKey = "speechLocale"
    /// Names and terms the recognizer should know (Settings → Captions & Summary → Vocabulary).
    static let vocabulary = VocabularyFileStore(appName: "Relaytake")

    static var engine: AppleSpeechEngine {
        AppleSpeechEngine(rawValue: UserDefaults.standard.string(forKey: engineKey) ?? "") ?? .speechTranscriber
    }

    /// An empty choice follows this Mac's language.
    static var locale: Locale {
        let identifier = UserDefaults.standard.string(forKey: localeKey) ?? ""
        return identifier.isEmpty ? .current : Locale(identifier: identifier)
    }
}

/// On-device speech-to-text for a recording, with the time each phrase covers. The recognizer, language
/// models, vocabulary and offline guard come from the shared PlainspokenSpeech package; audio never
/// leaves this Mac. The first use of a language may download the system's speech model through the system.
enum Transcriber {
    static func transcribe(
        videoAt url: URL, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> [CaptionSegment] {
        let transcript = try await FileTranscriber.transcribe(
            fileAt: url, engine: SpeechPreferences.engine, locale: SpeechPreferences.locale,
            vocabulary: SpeechPreferences.vocabulary.load()
        ) { update in
            let percent = Int((update.fraction * 100).rounded())
            switch update.stage {
            case .preparingModel: progress(update.fraction < 1 ? "Downloading the speech model \(percent)%…" : "Preparing the speech model…")
            case .transcribing: progress("Transcribing \(percent)%…")
            }
        }
        return transcript.segments.map { CaptionSegment(start: $0.start, end: $0.end, text: $0.text) }
    }
}
