import AppKit
import RelaytakeCore
import SwiftUI

// "Bug Report": a take becomes a ticket draft for a person: a title, a short description, steps to reproduce with a
// picture on each step, and expected and actual. The person edits it here, copies it as text for Jira, Slack,
// GitHub or a service desk, and attaches the pictures (dragged from the sheet) and the recording themselves.
// Everything is made on this Mac; Hot Take uploads nothing.

struct BugReportSession: Identifiable {
    let id = UUID()
    let files: TakeFiles
    var saved: BugReport.Saved
}

extension RecorderModel {
    /// The Watch page's *Bug Report*: reopens the draft made before, or makes one.
    func openBugReport(_ take: TakeEntry) {
        if let saved = BugReport.load(for: take.files) {
            bugReportSession = BugReportSession(files: take.files, saved: saved)
        } else {
            remakeBugReport(take.files)
        }
    }

    /// The Take menu's item (it was a straight copy before the draft sheet): opens the same draft sheet.
    func copyBugReport(_ take: TakeEntry) { openBugReport(take) }

    func remakeBugReport(_ files: TakeFiles) {
        runExclusively("Preparing your bug report…") { await self.makeBugReport(files) }
    }

    /// Makes the transcript if the take has none, drafts the ticket, takes the pictures and opens the draft.
    func makeBugReport(_ files: TakeFiles) async {
        var metadata = TakeLibrary.metadata(for: files)
        if metadata?.transcript.isEmpty ?? true {
            let notes = await Pipeline.process(
                take: files, created: metadata?.created ?? Date(), options: .init(captions: true, summary: false)
            ) { [weak self] text in self?.phase = .processing(text) }
            if !notes.isEmpty { message = notes.joined(separator: "\n") }
            metadata = TakeLibrary.metadata(for: files) ?? metadata
        }
        let take = metadata ?? TakeMetadata(title: files.baseName, summary: "", created: Date())

        do {
            let plan = try await AgentBrief.plan(for: files, metadata: take)
            var reading: BugReport.Reading?
            var steps: [Int: String] = [:]
            if !take.transcript.isEmpty, Summarizer.availabilityMessage == nil {
                // Without the model the draft still has the pictures and what was said, so a failure is not reported.
                phase = .processing("Reading the steps…")
                steps = (try? await Summarizer.bugSteps(moments: plan.moments, transcript: take.transcript)) ?? [:]
                phase = .processing("Writing the summary…")
                reading = try? await Summarizer.bugReading(transcript: Captions.plainText(take.transcript))
            }
            let draft = BugReport.draft(metadata: take, moments: plan.moments, steps: steps, reading: reading)
            phase = .processing("Taking pictures for your bug report…")
            let saved = try await BugReport.write(for: files, plan: plan, draft: draft) { [weak self] value in
                Task { @MainActor in self?.phase = .processing("Taking pictures for your bug report… \(Int(value * 100))%") }
            }
            bugReportSession = BugReportSession(files: files, saved: saved)
        } catch {
            message = "Could not make the bug report: \(error.localizedDescription)"
        }
    }
}

/// The Watch page button.
struct BugReportButton: View {
    let take: TakeEntry

    var body: some View {
        Button("Bug Report", systemImage: "ladybug") { RecorderModel.current?.openBugReport(take) }
            .fixedSize()
            .help("Draft a bug report for Jira, Slack or a service desk: steps to reproduce with a picture on each step, "
                + "expected and actual. Made on this Mac.")
    }
}

struct BugReportSheet: View {
    @State var session: BugReportSession
    @ObservedObject var recorder: RecorderModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("bugReportFormat") private var formatName = BugReport.Format.markdown.rawValue
    @State private var copied = ""

    private var format: BugReport.Format { BugReport.Format(rawValue: formatName) ?? .markdown }
    private var draft: Binding<BugReport.Draft> { $session.saved.draft }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Bug report").font(.title2.bold())
                    Text("Drafted on this Mac from what you said. Check it, fix anything, then copy it into your ticket or message.")
                        .font(.callout).foregroundStyle(.secondary)

                    field("Title") { TextField("Short title", text: draft.title).textFieldStyle(.roundedBorder) }
                    field("Summary") { editor(draft.summary, "What is wrong, and where") }
                    stepsSection
                    field("Expected") { editor(draft.expected, "What should have happened") }
                    field("Actual") { editor(draft.actual, "What happened instead") }
                    field("Environment") { editor(draft.environment, "Browser, app version, anything else (optional)") }
                }
                .padding(20)
            }
            Divider()
            footer.padding(14)
        }
        .frame(minWidth: 580, idealWidth: 640, minHeight: 560, idealHeight: 700)
        .onDisappear { try? BugReport.save(session.saved) }
    }

    private func field<Content: View>(_ name: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.headline)
            content()
        }
    }

    private func editor(_ text: Binding<String>, _ prompt: String) -> some View {
        TextField(prompt, text: text, axis: .vertical)
            .lineLimit(2...8)
            .textFieldStyle(.roundedBorder)
    }

    private var stepsSection: some View {
        field("Steps to reproduce") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(draft.steps) { $step in
                    HStack(alignment: .top, spacing: 10) {
                        picture(for: step)
                        TextField("Step (left empty, it is not used)", text: $step.text, axis: .vertical)
                            .lineLimit(1...4)
                            .textFieldStyle(.roundedBorder)
                        Button { session.saved.draft.steps.removeAll { $0.id == step.id } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this step")
                    }
                }
                Button("Add Step", systemImage: "plus") { session.saved.draft.steps.append(BugReport.Step(text: "")) }
                    .buttonStyle(.borderless)
                Text("Each picture shows where you clicked. Drag one into your ticket or message to attach it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func picture(for step: BugReport.Step) -> some View {
        if let number = step.picture, number >= 1, number <= session.saved.pictures.count {
            let url = session.saved.pictures[number - 1]
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .frame(width: 96, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
                    .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                    .help("Drag into your ticket or message")
            }
        } else {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 96, height: 60)
                .overlay(Text("No picture").font(.caption2).foregroundStyle(.secondary))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Format", selection: $formatName) {
                    ForEach(BugReport.Format.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .fixedSize()
                Text(format.detail).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !copied.isEmpty { Label(copied, systemImage: "checkmark").font(.caption).foregroundStyle(.green) }
            }
            HStack {
                Button("Copy Title") { copy(session.saved.draft.title, "Title copied") }
                    .disabled(session.saved.draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Copy Text") {
                    copy(BugReport.text(of: session.saved.draft, format: format, pictures: session.saved.pictureNames),
                         "Text copied")
                }
                .buttonStyle(.borderedProminent)
                .help(format == .slack ? "The title leads the message" : "The description for the ticket (copy the title separately)")
                Button("Show Pictures") { NSWorkspace.shared.activateFileViewerSelecting(session.saved.pictures) }
                Button("Show Recording") { NSWorkspace.shared.activateFileViewerSelecting([session.files.video]) }
                Spacer()
                Button("Start Over") {
                    let files = session.files
                    dismiss()
                    recorder.remakeBugReport(files)
                }
                .help("Draft it again from the recording, replacing your edits")
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("Hot Take uploads nothing. Attach the pictures and the recording to your ticket or message yourself.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func copy(_ text: String, _ message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        try? BugReport.save(session.saved)
        copied = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if copied == message { copied = "" }
        }
    }
}
