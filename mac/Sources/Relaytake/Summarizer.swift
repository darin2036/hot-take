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

    /// A long transcript is read in pieces, never just its start and end: each piece is summarized and the
    /// summaries stand in for the transcript (see `digest`).
    static func summarize(transcript: String) async throws -> (title: String, summary: String) {
        let text = try await digest(transcript)
        let session = LanguageModelSession(instructions: SummaryPrompt.instructions)
        let response = try await session.respond(to: SummaryPrompt.prompt(transcript: text))
        return SummaryPrompt.parse(response.content)
    }

    /// Writes one Info field from the transcript. Replies are cleaned (labels, quotes, bullets).
    /// Notes are collected from every piece of a long transcript; the other fields come from its digest.
    static func generate(_ field: MetadataField, transcript: String) async throws -> String {
        if field == .notes {
            let pieces = TranscriptChunks.split(transcript)
            if pieces.count > 1 {
                var found: [String] = []
                for piece in pieces {
                    try Task.checkCancellation()
                    found.append(try await generateOne(.notes, transcript: piece))
                }
                return MetadataPrompt.mergeNotes(found)
            }
        }
        return try await generateOne(field, transcript: try await digest(transcript))
    }

    private static func generateOne(_ field: MetadataField, transcript: String) async throws -> String {
        let session = LanguageModelSession(instructions: MetadataPrompt.instructions)
        let response = try await session.respond(to: MetadataPrompt.prompt(for: field, transcript: transcript))
        return MetadataPrompt.clean(response.content, for: field)
    }

    /// What the person in a walkthrough wants a coding agent to do. Nil when the reply had nothing usable.
    /// A long walkthrough is read in pieces, then the pieces' requests are merged.
    static func agentRequest(transcript: String) async throws -> AgentBrief.Request? {
        let pieces = TranscriptChunks.split(transcript)
        guard pieces.count > 1 else { return try await agentRequestOne(transcript) }
        var requests: [AgentBrief.Request] = []
        for piece in pieces {
            try Task.checkCancellation()
            if let request = try await agentRequestOne(piece) { requests.append(request) }
        }
        guard requests.count > 1 else { return requests.first }
        let merged = AgentPrompt.mergeText(requests)
        if merged.count <= SummaryPrompt.maxCharacters, let request = try await agentRequestOne(merged) { return request }
        return AgentPrompt.combined(requests)
    }

    private static func agentRequestOne(_ transcript: String) async throws -> AgentBrief.Request? {
        let session = LanguageModelSession(instructions: AgentPrompt.instructions)
        let response = try await session.respond(
            to: AgentPrompt.prompt(transcript: transcript), options: GenerationOptions(temperature: 0.2))
        return AgentPrompt.parse(response.content)
    }

    /// The transcript itself when it fits the model; otherwise one summary line per piece, summarized again
    /// until the result fits. If the model returns nothing for a piece, that piece is left out of the digest.
    private static func digest(_ transcript: String) async throws -> String {
        var text = transcript
        var rounds = 0
        while text.count > SummaryPrompt.maxCharacters, rounds < 4 {
            let pieces = TranscriptChunks.split(text)
            var parts: [String] = []
            for (index, piece) in pieces.enumerated() {
                try Task.checkCancellation()
                let session = LanguageModelSession(instructions: SummaryPrompt.instructions)
                let response = try await session.respond(
                    to: SummaryPrompt.partPrompt(piece, number: index + 1, of: pieces.count))
                let summary = SummaryPrompt.parse(response.content).summary
                if !summary.isEmpty { parts.append(summary) }
            }
            if parts.isEmpty { break }
            text = SummaryPrompt.digest(of: parts)
            rounds += 1
        }
        return text
    }

    /// Names one section of a recording. Nil when the reply is not a usable title; the caller keeps its own name.
    static func titleChapter(_ section: [CaptionSegment], number: Int, of count: Int) async throws -> String? {
        let session = LanguageModelSession(instructions: ChapterPrompt.instructions)
        let response = try await session.respond(
            to: ChapterPrompt.prompt(for: section, number: number, of: count), options: GenerationOptions(temperature: 0.2))
        return ChapterPrompt.parse(response.content)
    }

    /// Recommends cuts by segment number; times come from the transcript, never from the model.
    /// A long recording is checked a run of segments at a time, so cuts are found all the way through.
    static func recommendCuts(segments: [CaptionSegment]) async throws -> [EditSuggestion] {
        var cuts: [EditSuggestion] = []
        for run in TranscriptChunks.runs(of: segments) {
            try Task.checkCancellation()
            let part = Array(segments[run])
            let session = LanguageModelSession(instructions: EditPrompt.instructions)
            let response = try await session.respond(
                to: EditPrompt.prompt(for: part).text, options: GenerationOptions(temperature: 0.2))
            cuts += EditPrompt.parse(response.content, segments: part)
        }
        return Array(cuts.sorted { $0.span.start < $1.span.start }.prefix(10))
    }
}
