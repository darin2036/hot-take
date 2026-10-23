import AVFoundation
import Foundation
import RelaytakeCore

/// After a recording is saved: captions first, then a title and summary from the transcript.
/// Each step is optional and a failure in one never loses the video.
enum Pipeline {
    struct Options {
        var captions: Bool
        var summary: Bool
    }

    static func process(
        take: TakeFiles, created: Date, options: Options, progress: @escaping @MainActor (String) -> Void
    ) async -> [String] {
        var notes: [String] = []
        var transcript: [CaptionSegment] = []

        if options.captions || options.summary {
            await progress("Transcribing…")
            do {
                transcript = try await Transcriber.transcribe(videoAt: take.video) { text in
                    Task { @MainActor in progress(text) }
                }
                if options.captions && !transcript.isEmpty {
                    try Captions.webVTT(transcript).write(to: take.captions, atomically: true, encoding: .utf8)
                }
            } catch {
                notes.append("Captions: \(error.localizedDescription)")
            }
        }

        var title = take.baseName
        var summary = ""
        if options.summary && !transcript.isEmpty {
            await progress("Summarizing…")
            if let message = Summarizer.availabilityMessage {
                notes.append(message)
            } else {
                do {
                    let result = try await Summarizer.summarize(transcript: Captions.plainText(transcript))
                    title = result.title.isEmpty ? title : result.title
                    summary = result.summary
                } catch {
                    notes.append("Summary: \(error.localizedDescription)")
                }
            }
        }

        if !transcript.isEmpty || !summary.isEmpty {
            let seconds = try? await AVURLAsset(url: take.video).load(.duration).seconds
            var metadata = TakeMetadata(
                title: title, summary: summary, created: created, durationSeconds: seconds,
                transcript: transcript)
            // Running again on a take that already has notes must not erase what the user wrote.
            if let existing = TakeLibrary.metadata(for: take) {
                metadata.tags = existing.tags
                metadata.notes = existing.notes
                metadata.keepCapture(of: existing)
                if summary.isEmpty { metadata.summary = existing.summary }
                if title == take.baseName, !existing.title.isEmpty { metadata.title = existing.title }
            }
            do { try metadata.encoded().write(to: take.metadata, options: .atomic) } catch {
                notes.append("Metadata: \(error.localizedDescription)")
            }
        }
        return notes
    }
}
