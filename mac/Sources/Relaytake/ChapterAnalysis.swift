import AVFoundation
import Foundation
import RelaytakeCore

/// Proposes chapters for a take. Where they start comes from the transcript's words and timing (`ChapterDetector`);
/// the on-device model only names them. Nothing is saved here: the person decides what to keep.
enum ChapterAnalysis {
    struct Result {
        var chapters: [Chapter]
        var notes: [String]
    }

    static func run(for entry: TakeEntry, progress: @escaping @MainActor (String) -> Void) async -> Result {
        var notes: [String] = []
        let duration = (try? await AVURLAsset(url: entry.files.video).load(.duration).seconds) ?? 0

        let segments: [CaptionSegment]
        do { segments = try await Transcripts.ensure(for: entry, progress: progress) } catch {
            return Result(chapters: [], notes: ["Chapters are found from what is said, and there is no transcript: \(error.localizedDescription)"])
        }

        await progress("Looking for changes of subject…")
        var chapters = ChapterDetector.detect(segments: segments, duration: duration)
        if chapters.isEmpty {
            let length = max(duration, segments.last?.end ?? 0)
            notes.append(
                length < ChapterDetector.minimumRecording
                    ? "This recording is too short to need chapters."
                    : "No clear change of subject was found. You can still add chapters yourself at any point in the video.")
            return Result(chapters: [], notes: notes)
        }

        if let unavailable = Summarizer.availabilityMessage {
            notes.append("Titles are the section's own main words because \(unavailable)")
        } else {
            let sections = ChapterDetector.sections(of: segments, chapters: chapters)
            var failed = false
            for index in chapters.indices where !sections[index].isEmpty {
                await progress("Naming chapter \(index + 1) of \(chapters.count)…")
                do {
                    if let title = try await Summarizer.titleChapter(sections[index], number: index + 1, of: chapters.count) {
                        chapters[index].title = title
                    }
                } catch { failed = true }
            }
            if failed { notes.append("The model could not name every chapter, so those keep their main words as a title.") }
        }
        return Result(chapters: chapters, notes: notes)
    }
}
