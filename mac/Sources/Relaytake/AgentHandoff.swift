import AppKit
import RelaytakeCore
import SwiftUI

// "Record for an agent": a take becomes a request a coding agent can act on (what was said, a picture at each
// click, and a goal and steps from the on-device model when it is there), saved beside the take and copied so it
// can be pasted into Claude Code, Codex or Cursor. Everything is made on this Mac; pasting it anywhere is the
// user's own step.

extension RecorderModel {
    /// The Watch page's *Copy for Agent*.
    func copyForAgent(_ take: TakeEntry) {
        runExclusively("Preparing for your agent…") { await self.handOffToAgent(take.files) }
    }

    /// Makes the transcript if the take has none, writes the request beside the take and copies it.
    func handOffToAgent(_ files: TakeFiles) async {
        var metadata = TakeLibrary.metadata(for: files)
        if metadata?.transcript.isEmpty ?? true {
            let notes = await Pipeline.process(
                take: files, created: metadata?.created ?? Date(), options: .init(captions: true, summary: false)
            ) { [weak self] text in self?.phase = .processing(text) }
            if !notes.isEmpty { message = notes.joined(separator: "\n") }
            metadata = TakeLibrary.metadata(for: files) ?? metadata
        }
        let take = metadata ?? TakeMetadata(title: files.baseName, summary: "", created: Date())

        var request: AgentBrief.Request?
        if !take.transcript.isEmpty, Summarizer.availabilityMessage == nil {
            phase = .processing("Reading what you asked for…")
            // Without the model the request still has the walkthrough and transcript, so a failure here is not reported.
            request = try? await Summarizer.agentRequest(transcript: Captions.plainText(take.transcript))
        }

        phase = .processing("Taking pictures for your agent…")
        do {
            let output = try await AgentBrief.write(for: files, metadata: take, request: request) { [weak self] value in
                Task { @MainActor in self?.phase = .processing("Taking pictures for your agent… \(Int(value * 100))%") }
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(output.copyText, forType: .string)
            noticeFile = output.promptFile
            let count = output.pictures.count
            notice = "Copied a request for your coding agent with \(count) picture\(count == 1 ? "" : "s"). "
                + "Paste it into Claude Code, Codex or Cursor."
        } catch {
            message = "Could not prepare the recording for your agent: \(error.localizedDescription)"
        }
    }
}

/// The Watch page button.
struct CopyForAgentButton: View {
    let take: TakeEntry

    var body: some View {
        Button("For Agent", systemImage: "sparkles.rectangle.stack") { RecorderModel.current?.copyForAgent(take) }
            .fixedSize()
            .help("Copy this recording as a request for a coding agent: what you said, with a picture at each click. "
                + "Made on this Mac; paste it into Claude Code, Codex or Cursor.")
    }
}
