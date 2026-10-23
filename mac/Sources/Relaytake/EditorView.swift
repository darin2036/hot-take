import AVFoundation
import AppKit
import RelaytakeCore
import SwiftUI
import UniformTypeIdentifiers

/// Trim and cut: pick a range, then keep it or remove it. Save copy writes a new recording.
struct EditorView: View {
    let take: TakeEntry
    @ObservedObject var library: LibraryModel
    @ObservedObject var player: PlayerModel

    @State private var showFileSize = false
    @State private var sourceBytes = 0
    @State private var quality = "medium"
    @State private var includeAudio = true
    @State private var model = EditModel(duration: 0)
    @State private var selectionStart = 0.0
    @State private var selectionEnd = 0.0
    @State private var saving = false
    @State private var progress = 0.0
    @State private var status = ""
    @State private var task: Task<Void, Never>?

    private var duration: Double { player.duration }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { rangeControls; Spacer(minLength: 12); editControls }
                VStack(alignment: .leading, spacing: 10) { rangeControls; editControls }
            }
            .disabled(saving || duration == 0 || player.isPreviewingEdit)

            Timeline(
                model: model, duration: duration, playhead: player.isPreviewingEdit ? nil : player.time,
                start: $selectionStart, end: $selectionEnd, seek: { player.seek(to: $0) })
                .frame(height: 76)
                .disabled(saving || duration == 0 || player.isPreviewingEdit)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { playbackControls; Spacer(minLength: 12); outputControls }
                VStack(alignment: .leading, spacing: 10) {
                    playbackControls
                    HStack { Spacer(minLength: 0); outputControls }
                }
            }

            if !status.isEmpty {
                Text(status).font(.callout).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .controlSize(.regular)
        .buttonStyle(.bordered)
        .padding(14)
        .background(.bar)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: duration, initial: true) { _, value in
            guard value > 0, model.duration != value else { return }
            model = EditModel(duration: value)
            selectionStart = 0
            selectionEnd = value
        }
        .task { sourceBytes = (try? take.files.video.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        .onChange(of: library.cutRequests) { _, requests in
            guard !requests.isEmpty else { return }
            for span in requests {
                do { try model.remove(span) } catch { status = error.localizedDescription }
            }
            library.cutRequests = []
            selectionStart = 0
            selectionEnd = duration
        }
        .onDisappear { task?.cancel() }
    }

    private var playbackControls: some View {
        HStack(spacing: 10) {
            Toggle("Audio", isOn: $includeAudio).toggleStyle(.checkbox).disabled(saving)
            Button { togglePreview() } label: {
                Label(player.isPreviewingEdit ? "Stop preview" : "Preview",
                      systemImage: player.isPreviewingEdit ? "stop.fill" : "play.fill")
            }
            .disabled(saving || duration == 0)
            .help("Play the edited video")
            Text(timeLabel(model.keptDuration))
                .monospacedDigit().foregroundStyle(.secondary)
                .accessibilityLabel("Edited duration \(timeLabel(model.keptDuration))")
        }
    }

    private var outputControls: some View {
        HStack(spacing: 8) {
            Button { showFileSize.toggle() } label: {
                Label("File size", systemImage: "slider.horizontal.3")
            }
            .disabled(saving)
            .help("Adjust quality and estimated file size")
            .popover(isPresented: $showFileSize, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("File size").font(.headline)
                        Spacer()
                        Button("Done") { showFileSize = false }
                    }
                    QualityPicker(value: $quality, seconds: model.keptDuration, audio: includeAudio)
                    if sourceBytes > 0 {
                        Text("Original: \(ByteCountFormatter.string(fromByteCount: Int64(sourceBytes), countStyle: .file))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .controlSize(.regular)
                .padding(16).frame(width: 480)
            }
            if saving {
                ProgressView(value: progress).frame(maxWidth: 100)
                Button("Cancel") { task?.cancel() }
            }
            Menu("Export") {
                ForEach(VideoExportFormat.allCases) { format in
                    Button(format.title) { export(format) }
                        .disabled(!format.available)
                }
                if !VideoExportFormat.webm.available {
                    Text("WebM requires FFmpeg")
                }
            }
            .disabled(saving || duration == 0)
            Button { save() } label: { Label("Save copy", systemImage: "square.and.arrow.down") }
                .buttonStyle(.borderedProminent)
                .disabled(saving || duration == 0)
                .help("Save a separate video. The original stays unchanged. Cuts may differ by a few frames because export re-encodes the video.")
        }
    }

    private var rangeControls: some View {
        HStack(spacing: 6) {
            timeField("In", value: $selectionStart, lower: 0, upper: max(0, selectionEnd - 0.1))
            Button {
                selectionStart = max(0, min(player.time, selectionEnd - 0.1))
            } label: { Image(systemName: "arrow.left.to.line").frame(width: 16) }
                .help("Set In to playhead").accessibilityLabel("Set In to playhead")
            timeField("Out", value: $selectionEnd, lower: min(duration, selectionStart + 0.1), upper: duration)
            Button {
                selectionEnd = min(duration, max(player.time, selectionStart + 0.1))
            } label: { Image(systemName: "arrow.right.to.line").frame(width: 16) }
                .help("Set Out to playhead").accessibilityLabel("Set Out to playhead")
        }
    }

    private func timeField(_ title: String, value: Binding<Double>, lower: Double, upper: Double) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            TextField(title, value: Binding(get: { value.wrappedValue }, set: {
                guard $0.isFinite else { return }
                value.wrappedValue = max(lower, min(upper, $0))
            }), format: .number.precision(.fractionLength(1)))
                .monospacedDigit().multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder).frame(width: 68)
                .accessibilityLabel("\(title) point in seconds")
                .help("\(title) point in seconds")
        }
    }

    private var editControls: some View {
        HStack(spacing: 6) {
            Button { edit { try model.trim(to: selection) } } label: { Label("Trim", systemImage: "crop") }
                .help("Keep only the selected range")
            Button { edit { try model.remove(selection) } } label: { Label("Cut", systemImage: "scissors") }
                .help("Remove the selected range")
            Divider().frame(height: 18).padding(.horizontal, 3)
            Button { model.undo(); status = "" } label: { Image(systemName: "arrow.uturn.backward").frame(width: 16) }
                .disabled(!model.canUndo).help("Undo edit").accessibilityLabel("Undo edit")
            Button { model.reset(); status = "" } label: { Image(systemName: "arrow.counterclockwise").frame(width: 16) }
                .disabled(!model.isEdited).help("Reset edits").accessibilityLabel("Reset edits")
        }
    }

    private var selection: TimeSpan { TimeSpan(start: selectionStart, end: selectionEnd) }

    private func edit(_ change: () throws -> Void) {
        do {
            try change()
            status = ""
            selectionStart = 0
            selectionEnd = duration
        } catch { status = error.localizedDescription }
    }

    private func togglePreview() {
        Task {
            if player.isPreviewingEdit { await player.stopPreview(); return }
            do { try await player.previewEdit(model.segments) } catch { status = error.localizedDescription }
        }
    }

    private func export(_ format: VideoExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .movie]
        panel.nameFieldStringValue = take.files.baseName + "." + format.rawValue
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.standardizedFileURL.resolvingSymlinksInPath() != take.files.video.standardizedFileURL.resolvingSymlinksInPath() else {
            status = "Choose a different name to keep your original."; return
        }
        let segments = model.segments
        let encoding = EncodingPreferences.resolve(VideoQuality(rawValue: quality) ?? .medium)
        let audio = includeAudio
        saving = true; progress = 0; status = "Exporting \(format.rawValue.uppercased())…"
        task = Task {
            defer { saving = false; task = nil }
            do {
                try await VideoExport.save(asset: AVURLAsset(url: take.files.video), segments: segments,
                    to: url, format: format, quality: encoding, includeAudio: audio) { progress = $0 }
                status = "Exported “\(url.lastPathComponent)”."
            } catch is CancellationError { status = "Export canceled." }
            catch { status = "Could not export: \(error.localizedDescription)" }
        }
    }

    private func save() {
        saving = true
        progress = 0
        status = "Saving copy…"
        let source = AVURLAsset(url: take.files.video)
        let name = TakeLibrary.uniqueCopyName(basedOn: take.files.baseName, in: take.files.directory)
        let copy = TakeFiles(directory: take.files.directory, baseName: name)
        let segments = model.segments
        let encoding = EncodingPreferences.resolve(VideoQuality(rawValue: quality) ?? .medium)
        let hasCuts = model.isEdited
        let created = Date()
        task = Task {
            defer { saving = false; task = nil }
            do {
                try await Exporter.save(asset: source, segments: segments, to: copy.video, quality: encoding, includeAudio: includeAudio) { progress = $0 }
                try Task.checkCancellation()
                var notes: [String] = []
                if hasCuts {
                    let defaults = UserDefaults.standard
                    let wants = { (key: String) in defaults.object(forKey: key) as? Bool ?? true }
                    notes = await Pipeline.process(
                        take: copy, created: created,
                        options: .init(captions: wants(Pref.captions), summary: wants(Pref.summary))
                    ) { status = $0 }
                } else {
                    // Compression does not change the timeline: preserve captions and notes.
                    var metadata = TakeLibrary.metadata(for: take.files) ?? TakeMetadata(
                        title: take.title, summary: take.summary, created: created)
                    metadata.created = created
                    metadata.durationSeconds = model.keptDuration
                    do {
                        try metadata.encoded().write(to: copy.metadata, options: .atomic)
                        if FileManager.default.fileExists(atPath: take.files.captions.path) {
                            try FileManager.default.copyItem(at: take.files.captions, to: copy.captions)
                        }
                    } catch { notes.append("Video saved; notes could not be copied.") }
                }
                library.select(files: copy)
                status = notes.isEmpty ? "Saved “\(name)”." : "Saved “\(name)”. " + notes.joined(separator: " ")
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: copy.video)
                status = "Canceled. No copy was kept."
            } catch {
                status = "Could not save: \(error.localizedDescription)"
            }
        }
    }
}

/// Kept sections are filled, removed sections are grey; drag the handles to select a range.
private struct Timeline: View {
    let model: EditModel
    let duration: Double
    let playhead: Double?
    @Binding var start: Double
    @Binding var end: Double
    let seek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 12)
            let x = { (time: Double) in duration > 0 ? CGFloat(max(0, min(duration, time)) / duration) * width : 0 }
            let time = { (position: CGFloat) in duration > 0 ? Double(max(0, min(width, position)) / width) * duration : 0 }

            VStack(spacing: 5) {
                Canvas { context, size in
                    for index in 0...4 {
                        let fraction = Double(index) / 4
                        let position = size.width * fraction
                        let label = Text(timeLabel(duration * fraction))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                        context.draw(label, at: CGPoint(x: position, y: 6),
                                     anchor: index == 0 ? .topLeading : index == 4 ? .topTrailing : .top)
                    }
                }
                .frame(height: 22)
                .accessibilityHidden(true)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    ForEach(Array(model.segments.enumerated()), id: \.offset) { _, segment in
                        RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.32))
                            .frame(width: max(1, x(segment.end) - x(segment.start)))
                            .offset(x: x(segment.start))
                    }
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 2))
                        .frame(width: max(0, x(end) - x(start))).offset(x: x(start))
                        .allowsHitTesting(false)
                    if let playhead {
                        Rectangle().fill(Color.primary).frame(width: 2).offset(x: x(playhead) - 1)
                            .overlay(alignment: .topLeading) {
                                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9))
                                    .offset(x: x(playhead) - 5, y: -5)
                            }
                            .allowsHitTesting(false)
                    }
                    handle("In", value: $start, lower: 0, upper: max(0, end - 0.1)).offset(x: x(start) - 6)
                        .gesture(DragGesture(coordinateSpace: .named("timeline")).onChanged {
                            start = max(0, min(time($0.location.x), end - 0.1))
                        })
                    handle("Out", value: $end, lower: min(duration, start + 0.1), upper: duration).offset(x: x(end) - 6)
                        .gesture(DragGesture(coordinateSpace: .named("timeline")).onChanged {
                            end = min(duration, max(time($0.location.x), start + 0.1))
                        })
                }
                .frame(height: 44)
                .coordinateSpace(name: "timeline")
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture(coordinateSpace: .named("timeline")).onEnded { seek(time($0.location.x)) })
            }
            .padding(.horizontal, 6)
        }
    }

    private func handle(_ title: String, value: Binding<Double>, lower: Double, upper: Double) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(Color.accentColor).frame(width: 12, height: 44)
            .overlay(Capsule().fill(.white.opacity(0.9)).frame(width: 2, height: 18))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.5)))
            .accessibilityLabel("\(title) point")
            .accessibilityValue(timeLabel(value.wrappedValue))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.1 : -0.1
                value.wrappedValue = max(lower, min(upper, value.wrappedValue + step))
            }
            .help("Drag to set \(title.lowercased()) point")
    }
}
