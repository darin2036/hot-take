import AVFoundation
import Foundation
import RelaytakeCore

/// Finds places a take could be tightened: long pauses (measured from the audio and the transcript's timing) and
/// restarts (found by comparing neighbouring transcript lines, then checked by the on-device model if it is there), and,
/// if asked, filler sounds like "um" and "uh" (from the recognizer's word timings). Nothing here changes the video.
enum EditAnalysis {
    struct Result {
        var suggestions: [EditSuggestion]
        var notes: [String]
        var noiseThreshold: Double?
    }

    /// `pauseLength` is the shortest pause, in seconds, worth proposing.
    static func run(
        for entry: TakeEntry, pauseLength: Double = 2, fillers findFillers: Bool = false, restarts findRestarts: Bool = true,
        progress: @escaping @MainActor (String) -> Void
    ) async -> Result {
        var notes: [String] = []
        var audioSilences: [TimeSpan] = []
        var gaps: [TimeSpan] = []
        var restarts: [EditSuggestion] = []
        var recommended: [EditSuggestion] = []
        var fillers: [EditSuggestion] = []
        var threshold: Double?

        let duration = (try? await AVURLAsset(url: entry.files.video).load(.duration).seconds) ?? 0

        await progress("Measuring audio levels…")
        do {
            let levels = try await AudioLevels.analyze(url: entry.files.video)
            if levels.isEmpty {
                notes.append("This recording has no audio, so quiet parts can't be measured.")
            } else {
                let limit = SilenceDetector.threshold(levels: levels)
                threshold = limit
                let quiet = SilenceDetector.quietSpans(
                    levels: levels, windowSeconds: AudioLevels.windowSeconds, thresholdDB: limit, minDuration: pauseLength)
                // Leave a little breathing room at each end of a pause so the cut does not clip a word.
                audioSilences = SilenceDetector.trimmed(quiet, by: 0.3, minLength: 0.4)
            }
        } catch {
            notes.append("Audio could not be analyzed: \(error.localizedDescription)")
        }

        var segments: [CaptionSegment] = []
        do {
            segments = try await Transcripts.ensure(for: entry, progress: progress)
            gaps = SilenceDetector.trimmed(
                TranscriptGaps.gaps(segments: segments, duration: duration, minGap: pauseLength), by: 0.3, minLength: 0.4)
        } catch {
            notes.append("No transcript, so recommendations are limited to quiet parts: \(error.localizedDescription)")
        }

        if findRestarts, !segments.isEmpty {
            restarts = RestartFinder.find(in: segments)
            if let unavailable = Summarizer.availabilityMessage {
                notes.append(unavailable + " Pauses and repeated sentences were still found; other restarts need it.")
            } else {
                await progress("Checking for restarts…")
                do { recommended = try await Summarizer.recommendCuts(segments: segments) } catch {
                    notes.append("The model could not check for restarts: \(error.localizedDescription)")
                }
            }
        }

        if findFillers {
            if SpeechPreferences.locale.language.languageCode != .english {
                notes.append("Filler words are only recognized in English recordings.")
            } else {
                do {
                    fillers = FillerWords.find(in: try await Transcripts.words(for: entry, progress: progress))
                } catch {
                    notes.append("Filler words could not be found: \(error.localizedDescription)")
                }
            }
        }

        return Result(
            suggestions: EditSuggestions.combine(
                audioSilences: audioSilences, transcriptGaps: gaps, restarts: restarts, recommended: recommended,
                fillers: fillers),
            notes: notes, noiseThreshold: threshold)
    }
}
