import Foundation
import RelaytakeCore

/// The transcript of a take: read from its notes file, or made on this Mac (and saved) if missing.
enum Transcripts {
    static func ensure(for entry: TakeEntry, progress: @escaping @MainActor (String) -> Void = { _ in }) async throws -> [CaptionSegment] {
        if let existing = TakeLibrary.metadata(for: entry.files)?.transcript, !existing.isEmpty { return existing }
        await progress("Transcribing…")
        let segments = try await Transcriber.transcribe(videoAt: entry.files.video) { text in
            Task { @MainActor in progress(text) }
        }
        if !segments.isEmpty { try? TakeLibrary.update(entry) { $0.transcript = segments } }
        return segments
    }
}
