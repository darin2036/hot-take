import Foundation
import RelaytakeCore

/// The transcript of a take: read from its notes file, or made on this Mac (and saved) if missing.
enum Transcripts {
    static func ensure(for entry: TakeEntry, progress: @escaping @MainActor (String) -> Void = { _ in }) async throws -> [CaptionSegment] {
        if let existing = TakeLibrary.metadata(for: entry.files)?.transcript, !existing.isEmpty { return existing }
        await progress("Transcribing…")
        let heard = try await Transcriber.listen(to: entry.files.video) { text in
            Task { @MainActor in progress(text) }
        }
        if !heard.segments.isEmpty {
            try? TakeLibrary.update(entry) {
                $0.transcript = heard.segments
                if heard.keepsFillers { $0.words = heard.words }
            }
        }
        return heard.segments
    }

    /// Every word of the take with its timing, filler sounds included: saved from an earlier pass, or heard now with
    /// SpeechTranscriber (whatever Settings chooses, since the classic model drops "um" and "uh") and saved. The
    /// transcript itself, with any corrections, is left as it is.
    static func words(for entry: TakeEntry, progress: @escaping @MainActor (String) -> Void = { _ in }) async throws -> [TimedWord] {
        if let existing = TakeLibrary.metadata(for: entry.files)?.words, !existing.isEmpty { return existing }
        await progress("Listening for filler words…")
        let heard = try await Transcriber.listen(to: entry.files.video, engine: .speechTranscriber) { text in
            Task { @MainActor in progress(text) }
        }
        if !heard.words.isEmpty {
            try? TakeLibrary.update(entry) {
                $0.words = heard.words
                if $0.transcript.isEmpty { $0.transcript = heard.segments }
            }
        }
        return heard.words
    }
}
