import Foundation
import RelaytakeCore

/// Writes a take's summary from its whole transcript with the on-device model, for the Watch and Transcript
/// pages. The transcript is made first if there is none; the summary it replaces is kept for Undo.
/// Nothing is sent off this Mac.
@MainActor
final class SummaryJob: ObservableObject {
    /// Progress text while working; nil when idle.
    @Published private(set) var status: String?
    @Published private(set) var note = ""
    @Published private(set) var previous: String?
    /// Bumped whenever the saved summary changes, so views showing it can reload.
    @Published private(set) var revision = 0

    var isRunning: Bool { status != nil }

    func run(for take: TakeEntry, library: LibraryModel) {
        guard !isRunning else { return }
        status = "Reading transcript…"
        note = ""
        Task {
            defer { status = nil }
            do {
                let segments = try await Transcripts.ensure(for: take) { self.status = $0 }
                let transcript = Captions.plainText(segments)
                guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    note = "No speech was found in this recording, so there is nothing to summarize."
                    return
                }
                status = "Summarizing…"
                let text = try await Summarizer.generate(.summary, transcript: transcript)
                guard !text.isEmpty else {
                    note = "The model found nothing to summarize."
                    return
                }
                let old = TakeLibrary.metadata(for: take.files)?.summary ?? ""
                guard text != old else { return }
                try TakeLibrary.update(take) { $0.summary = text }
                previous = old
                revision += 1
                library.refresh()
            } catch {
                note = "Could not summarize: \(error.localizedDescription)"
            }
        }
    }

    func undo(for take: TakeEntry, library: LibraryModel) {
        guard let old = previous else { return }
        do {
            try TakeLibrary.update(take) { $0.summary = old }
            previous = nil
            revision += 1
            library.refresh()
        } catch {
            note = "Could not undo: \(error.localizedDescription)"
        }
    }
}
