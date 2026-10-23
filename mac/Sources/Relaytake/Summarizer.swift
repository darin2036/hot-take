import Foundation
import FoundationModels
import RelaytakeCore

/// Titles and summaries from the system's on-device foundation model. Nothing is sent to a server.
/// Uses plain text with a fixed format instead of @Generable, so the package builds with just the
/// command line tools (the macro plugin ships only with the full developer tools).
enum Summarizer {
    static var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(let reason): "on-device intelligence is unavailable (\(reason))."
        }
    }

    static func summarize(transcript: String) async throws -> (title: String, summary: String) {
        let session = LanguageModelSession(instructions: SummaryPrompt.instructions)
        let response = try await session.respond(to: SummaryPrompt.prompt(transcript: transcript))
        return SummaryPrompt.parse(response.content)
    }

    /// Writes one Info field from the transcript. Replies are cleaned (labels, quotes, bullets).
    static func generate(_ field: MetadataField, transcript: String) async throws -> String {
        let session = LanguageModelSession(instructions: MetadataPrompt.instructions)
        let response = try await session.respond(to: MetadataPrompt.prompt(for: field, transcript: transcript))
        return MetadataPrompt.clean(response.content, for: field)
    }

    /// Recommends cuts by segment number; times come from the transcript, never from the model.
    static func recommendCuts(segments: [CaptionSegment]) async throws -> [EditSuggestion] {
        let session = LanguageModelSession(instructions: EditPrompt.instructions)
        let prompt = EditPrompt.prompt(for: segments)
        let response = try await session.respond(
            to: prompt.text, options: GenerationOptions(temperature: 0.2))
        return EditPrompt.parse(response.content, segments: Array(segments.prefix(prompt.included)))
    }
}
