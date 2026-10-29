import AVFoundation
import AppKit
import CoreMedia
import RelaytakeCore
import SwiftUI

/// Edit what Hot Take knows about a take (title, summary, tags, notes) and see facts about the file.
/// Edits save by themselves a moment after you stop typing.
struct InfoView: View {
    let take: TakeEntry
    @ObservedObject var library: LibraryModel

    private struct Draft: Equatable {
        var title = ""
        var summary = ""
        var tags = ""
        var notes = ""

        subscript(field: MetadataField) -> String {
            get {
                switch field {
                case .title: title
                case .summary: summary
                case .tags: tags
                case .notes: notes
                }
            }
            set {
                switch field {
                case .title: title = newValue
                case .summary: summary = newValue
                case .tags: tags = newValue
                case .notes: notes = newValue
                }
            }
        }
    }

    @State private var draft = Draft()
    @State private var saved = Draft()
    @State private var status = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var facts: [(label: String, value: String)] = []
    /// Fields the on-device model is writing right now, and what each held before it did.
    @State private var generating: Set<MetadataField> = []
    @State private var previous: [MetadataField: String] = [:]
    @State private var aiNote = ""
    /// Progress text while captions are being made.
    @State private var showFile = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("Info").font(.title3.bold())
                    Spacer()
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Button { generate(MetadataField.allCases) } label: { Label("Generate", systemImage: "sparkles") }
                        .controlSize(.small)
                        .disabled(!generating.isEmpty || aiUnavailable != nil)
                        .help(aiUnavailable ?? "Write the title, summary, tags and notes from the transcript, on this Mac")
                }
                fieldRow(.title) {
                    TextField("Title", text: $draft.title).textFieldStyle(.roundedBorder)
                }
                fieldRow(.tags) {
                    TextField("Tags", text: $draft.tags).textFieldStyle(.roundedBorder)
                        .help("Separate tags with commas")
                }
                fieldRow(.summary) { editor($draft.summary, minHeight: 110) }
                fieldRow(.notes) { editor($draft.notes, minHeight: 80) }
                if !aiNote.isEmpty { Text(aiNote).font(.caption).foregroundStyle(.secondary).help(aiNote) }
                Divider()
                fileFacts
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .task(id: take.id) {
            let metadata = TakeLibrary.metadata(for: take.files)
            let loaded = Draft(
                title: take.title == TakeEntry.untitled ? (metadata?.title ?? "") : take.title,
                summary: metadata?.summary ?? "", tags: (metadata?.tags ?? []).joined(separator: ", "),
                notes: metadata?.notes ?? "")
            draft = loaded
            saved = loaded
            status = ""
            facts = await FileFacts.load(take: take, library: library)
        }
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onDisappear { saveNow() }
    }

    // MARK: Editable metadata

    private var aiUnavailable: String? { Summarizer.availabilityMessage }

    /// A field with its label, a Generate button (the on-device model writes it) and Undo for that write.
    private func fieldRow<Content: View>(_ field: MetadataField, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(field.label).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if let old = previous[field] {
                    Button("Undo") {
                        draft[field] = old
                        previous[field] = nil
                    }
                    .buttonStyle(.link).font(.caption)
                    .help("Put back what was here before it was generated")
                }
                if generating.contains(field) {
                    ProgressView().controlSize(.small)
                } else {
                    Button { generate([field]) } label: { Image(systemName: "sparkles") }
                        .buttonStyle(.borderless)
                        .disabled(!generating.isEmpty || aiUnavailable != nil)
                        .help(aiUnavailable ?? "Write this \(field.rawValue) with the on-device model")
                }
            }
            content()
        }
    }

    /// Writes the given fields from the transcript, making the transcript first if there is none.
    /// What each field held is kept so it can be undone; nothing is sent off this Mac.
    private func generate(_ fields: [MetadataField]) {
        generating = Set(fields)
        aiNote = ""
        Task {
            defer { generating = [] }
            do {
                let segments = try await Transcripts.ensure(for: take) { status = $0 }
                let transcript = Captions.plainText(segments)
                guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    aiNote = "No speech was found in this recording, so there is nothing to write from."
                    status = ""
                    return
                }
                for field in fields {
                    status = "Writing \(field.rawValue)…"
                    let text = try await Summarizer.generate(field, transcript: transcript)
                    if text != draft[field] {
                        previous[field] = draft[field]
                        draft[field] = text
                    }
                }
                status = ""
                if fields.contains(where: { draft[$0].isEmpty }) {
                    aiNote = "The model found nothing to put in " + fields.filter { draft[$0].isEmpty }.map(\.rawValue).joined(separator: ", ") + "."
                }
            } catch {
                aiNote = "Could not generate: \(error.localizedDescription)"
                status = ""
            }
        }
    }

    private func editor(_ text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(minHeight: minHeight)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
    }

    // MARK: Saving

    private func scheduleSave() {
        guard draft != saved else { return }
        status = "Editing…"
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled { saveNow() }
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        guard draft != saved else { return }
        let snapshot = draft
        let before = saved
        do {
            // Only the fields edited here are written, so a summary written from the Watch page meanwhile stays.
            try TakeLibrary.update(take) { metadata in
                if snapshot.title != before.title { metadata.title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines) }
                if snapshot.summary != before.summary { metadata.summary = snapshot.summary }
                if snapshot.tags != before.tags { metadata.tags = TakeMetadata.parseTags(snapshot.tags) }
                if snapshot.notes != before.notes { metadata.notes = snapshot.notes }
            }
            saved = snapshot
            status = "Saved"
            library.refresh()
        } catch {
            status = "Could not save: \(error.localizedDescription)"
        }
    }

    // MARK: File facts

    private var fileFacts: some View {
        DisclosureGroup(isExpanded: $showFile) {
            VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 5) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    GridRow {
                        Text(fact.label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Text(fact.value).lineLimit(2).help(fact.value).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .font(.callout)
            Button("Show in Folder", systemImage: "magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting([take.files.video])
            }
            .controlSize(.small)
            }
            .padding(.top, 6)
        } label: {
            Text("File").font(.headline)
        }
    }
}

/// Reads size, duration, resolution and codecs from the file itself.
private enum FileFacts {
    static func load(take: TakeEntry, library: LibraryModel) async -> [(label: String, value: String)] {
        var rows: [(String, String)] = []
        let url = take.files.video
        rows.append(("Name", url.lastPathComponent))
        rows.append(("Folder", take.folder.isEmpty ? "Top level" : take.folder))

        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        if let bytes = values?.fileSize {
            rows.append(("Size", ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)))
        }

        let asset = AVURLAsset(url: url)
        if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite {
            rows.append(("Duration", timeLabel(seconds)))
        }
        if let video = try? await asset.loadTracks(withMediaType: .video).first {
            if let size = try? await video.load(.naturalSize), let transform = try? await video.load(.preferredTransform) {
                let rect = CGRect(origin: .zero, size: size).applying(transform)
                rows.append(("Resolution", "\(Int(abs(rect.width))) × \(Int(abs(rect.height)))"))
            }
            if let fps = try? await video.load(.nominalFrameRate), fps > 0 {
                rows.append(("Frame rate", "\(Int(fps.rounded())) fps"))
            }
            if let descriptions = try? await video.load(.formatDescriptions), let first = descriptions.first {
                rows.append(("Video", codecName(CMFormatDescriptionGetMediaSubType(first))))
            }
            if let rate = try? await video.load(.estimatedDataRate), rate > 0 {
                rows.append(("Video bit rate", "\(Int((rate / 1000).rounded())) kbps"))
            }
        }
        let audio = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        if let track = audio.first, let first = try? await track.load(.formatDescriptions).first {
            var text = codecName(CMFormatDescriptionGetMediaSubType(first))
            if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(first)?.pointee {
                text += basic.mChannelsPerFrame == 1 ? ", mono" : basic.mChannelsPerFrame == 2 ? ", stereo" : ", \(basic.mChannelsPerFrame) channels"
                text += ", \(Int(basic.mSampleRate / 1000)) kHz"
            }
            if audio.count > 1 { text += " (+\(audio.count - 1) more track\(audio.count > 2 ? "s" : ""))" }
            rows.append(("Audio", text))
        } else {
            rows.append(("Audio", "None"))
        }

        rows.append(("Captions", take.hasCaptions ? "Yes (.vtt beside the video)" : "None"))
        rows.append(("Recorded", take.created.formatted(date: .long, time: .shortened)))
        if let modified = values?.contentModificationDate {
            rows.append(("Modified", modified.formatted(date: .long, time: .shortened)))
        }
        return rows
    }

    static func codecName(_ code: FourCharCode) -> String {
        let text = String(
            (0..<4).map { Character(UnicodeScalar(UInt8((code >> UInt32(24 - 8 * $0)) & 0xFF))) })
        switch text {
        case "avc1", "avc3": return "H.264"
        case "hvc1", "hev1": return "HEVC (H.265)"
        case "mp4a": return "AAC"
        case "ac-3": return "AC-3"
        case "alac": return "ALAC (lossless)"
        default: return text.trimmingCharacters(in: .whitespaces)
        }
    }
}
