import Foundation
import RelaytakeCore
import Translation

/// Translates a transcript with the system's Translation framework. It runs on this Mac: the system may ask to
/// download a language the first time (through the session SwiftUI's `translationTask` provides, which is the
/// only way to get that permission prompt), and no text is sent to a server by this app.
enum CaptionTranslator {
    struct Language: Identifiable, Hashable {
        let id: String
        let name: String
    }

    static func name(for identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    /// Languages the system can translate into, by name, leaving out the one the recording is in.
    static func targets(excluding source: Locale.Language) async -> [Language] {
        var seen = Set<String>()
        return await LanguageAvailability().supportedLanguages
            .filter { $0.languageCode != source.languageCode }
            .map { Language(id: $0.minimalIdentifier, name: name(for: $0.minimalIdentifier)) }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Translates every line, one request each so the timing stays with its line. `progress` gets (done, total).
    static func translate(
        _ segments: [CaptionSegment], with session: TranslationSession, progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [CaptionSegment] {
        let requests = CaptionTranslation.requests(for: segments)
        let batch = requests.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: String($0.line)) }
        var translated: [Int: String] = [:]
        for try await response in session.translate(batch: batch) {
            if let id = response.clientIdentifier, let line = Int(id) { translated[line] = response.targetText }
            progress(translated.count, requests.count)
        }
        return try CaptionTranslation.merge(segments, translated: translated)
    }
}
