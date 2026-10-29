import AVFoundation
import AppKit
import RelaytakeCore
import SwiftUI
import UniformTypeIdentifiers

// Things done to recordings that are already in the library: joining several into one, importing videos made
// elsewhere, and taking pictures out of a recording (a thumbnail, a GIF, a still at each click). They report
// through the same status banner as recording does. Originals are never changed.

extension RecorderModel {
    /// Runs `work` with the status banner showing `text`, and only when nothing else is going on.
    func runExclusively(_ text: String, _ work: @escaping @MainActor () async -> Void) {
        guard phase == .idle else {
            message = "Wait for the current recording or task to finish, then try again."
            return
        }
        message = ""
        notice = ""
        phase = .processing(text)
        Task {
            await work()
            phase = .idle
            LibraryModel.shared.refresh()
        }
    }

    // MARK: Import

    func importVideos(_ urls: [URL]) {
        let videos = urls.filter { VideoImporter.fileExtensions.contains($0.pathExtension.lowercased()) }
        guard !videos.isEmpty else {
            message = "Choose MP4, MOV or M4V videos to import."
            return
        }
        let destination = directory
        runExclusively("Importing…") {
            var last: TakeFiles?
            var problems: [String] = []
            var imported = 0
            for (index, url) in videos.enumerated() {
                let step = videos.count > 1 ? " (\(index + 1) of \(videos.count))" : ""
                self.phase = .processing("Importing\(step)…")
                do {
                    let files = try await VideoImporter.importVideo(from: url, into: destination)
                    imported += 1
                    last = files
                    LibraryModel.shared.refresh()
                    let options = Pipeline.Options(captions: self.flag(Pref.captions), summary: self.flag(Pref.summary))
                    problems += await Pipeline.process(take: files, created: Date(), options: options) { [weak self] text in
                        self?.phase = .processing(text + step)
                    }
                } catch { problems.append(error.localizedDescription) }
            }
            if let last, imported == 1 { LibraryModel.shared.select(files: last) }
            if problems.isEmpty {
                self.notice = imported == 1 ? "Imported the video into your library." : "Imported \(imported) videos into your library."
            } else {
                self.message = problems.joined(separator: "\n")
            }
        }
    }

    // MARK: Join

    /// Joins recordings, in the order they were recorded, into a new take beside the first one. The originals stay.
    func join(_ takes: [TakeEntry]) {
        let ordered = takes.sorted { $0.created < $1.created }
        guard ordered.count >= 2 else { message = JoinError.needsTwo.localizedDescription; return }
        let created = Date()
        let files = TakeFiles(directory: ordered[0].files.directory, baseName: TakeFiles.baseName(for: created))
        runExclusively("Joining \(ordered.count) recordings…") {
            do {
                try await TakeJoiner.join(ordered.map(\.files.video), to: files.video) { [weak self] value in
                    Task { @MainActor in self?.phase = .processing("Joining \(ordered.count) recordings… \(Int(value * 100))%") }
                }
                // Clicks carry over, so Auto Zoom and click rings work on the joined take too.
                var parts: [(clicks: [ClickEvent], duration: Double)] = []
                for take in ordered {
                    let length = (try? await AVURLAsset(url: take.files.video).load(.duration).seconds) ?? 0
                    parts.append((TakeLibrary.metadata(for: take.files)?.clicks ?? [], length))
                }
                let kinds = Set(ordered.compactMap { TakeLibrary.metadata(for: $0.files)?.captureKind })
                var metadata = TakeMetadata(
                    title: JoinPlan.title(for: ordered.map(\.title)), summary: "", created: created,
                    durationSeconds: parts.map(\.duration).reduce(0, +))
                metadata.clicks = JoinPlan.mergedClicks(parts)
                metadata.captureKind = kinds.count == 1 ? kinds.first : nil
                try metadata.encoded().write(to: files.metadata, options: .atomic)
                LibraryModel.shared.refresh()
                let options = Pipeline.Options(captions: self.flag(Pref.captions), summary: self.flag(Pref.summary))
                let notes = await Pipeline.process(take: files, created: created, options: options) { [weak self] text in
                    self?.phase = .processing(text)
                }
                LibraryModel.shared.clearSelection()
                LibraryModel.shared.select(files: files)
                if !notes.isEmpty { self.message = notes.joined(separator: "\n") }
            } catch {
                try? FileManager.default.removeItem(at: files.video)
                try? FileManager.default.removeItem(at: files.metadata)
                self.message = "Could not join: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Pictures from a recording

    func exportGIF(of take: TakeEntry, start: Double, length: Double, width: Int, fps: Double, to url: URL) {
        runExclusively("Making the GIF…") {
            do {
                try await GIFExporter.export(
                    asset: AVURLAsset(url: take.files.video), start: start, length: length, fps: fps, maxWidth: width, to: url
                ) { [weak self] value in
                    Task { @MainActor in self?.phase = .processing("Making the GIF… \(Int(value * 100))%") }
                }
                self.noticeFile = url
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                self.notice = "Saved “\(url.lastPathComponent)” (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))."
            } catch {
                self.message = error.localizedDescription
            }
        }
    }

    /// Saves a picture at each click that was noted while recording, into a new folder inside `parent`.
    func saveClickFrames(of take: TakeEntry, into parent: URL) {
        runExclusively("Saving pictures…") {
            do {
                let asset = AVURLAsset(url: take.files.video)
                let duration = try await asset.load(.duration).seconds
                let times = ClickFrames.moments(clicks: TakeLibrary.metadata(for: take.files)?.clicks ?? [], duration: duration)
                guard !times.isEmpty else {
                    self.message = "No clicks were noted for this recording, so there are no pictures to save."
                    return
                }
                let folder = ClickFrames.uniqueFolder(in: parent, title: take.title)
                let files = try await ClickFrames.export(asset: asset, times: times, to: folder) { [weak self] value in
                    Task { @MainActor in self?.phase = .processing("Saving pictures… \(Int(value * 100))%") }
                }
                self.noticeFile = folder
                self.notice = "Saved \(files.count) picture\(files.count == 1 ? "" : "s") in “\(folder.lastPathComponent)”."
            } catch {
                self.message = "Could not save the pictures: \(error.localizedDescription)"
            }
        }
    }
}

extension LibraryModel {
    /// File ▸ Import Video…
    func chooseAndImportVideos() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = VideoImporter.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.message = "Choose videos to add to your library. The originals are not changed."
        panel.prompt = "Import"
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        RecorderModel.current?.importVideos(panel.urls)
    }
}
// MARK: Watch page: speed and "More"

/// Playback speed for the recording being watched.
struct SpeedMenu: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        Menu {
            Picker("Speed", selection: $player.speed) {
                ForEach(PlaybackSpeed.choices, id: \.self) { Text(PlaybackSpeed.label($0)).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(PlaybackSpeed.label(player.speed), systemImage: "speedometer")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Playback speed")
    }
}

/// Pictures from this recording: a thumbnail, a GIF, and a still at each click.
struct TakePicturesMenu: View {
    let take: TakeEntry
    @ObservedObject var library: LibraryModel
    @ObservedObject var player: PlayerModel
    @State private var showGIF = false

    var body: some View {
        Menu {
            Button("Use This Frame as the Thumbnail", systemImage: "photo") {
                library.setThumbnail(for: take, at: player.time)
                RecorderModel.current?.notice = "The frame at \(timeLabel(player.time)) is now this recording's thumbnail."
            }
            .help("Pause on the picture you want, then choose this. The library shows it for this recording.")
            Button("Save as GIF…", systemImage: "photo.stack") { showGIF = true }
            Button("Save a Picture at Each Click…", systemImage: "cursorarrow.click.2") { chooseFolderForClickFrames() }
        } label: {
            Label("Pictures", systemImage: "photo.on.rectangle")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Thumbnail, GIF, and pictures at each click")
        .popover(isPresented: $showGIF, arrowEdge: .bottom) {
            GIFPanel(take: take, start: player.time, close: { showGIF = false })
        }
    }

    private func chooseFolderForClickFrames() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to put a new folder with a picture of each click."
        panel.prompt = "Save Here"
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        RecorderModel.current?.saveClickFrames(of: take, into: parent)
    }
}

private struct GIFPanel: View {
    let take: TakeEntry
    let start: Double
    let close: () -> Void
    @AppStorage("gifLength") private var length = 5.0
    @AppStorage("gifWidth") private var width = 640
    @AppStorage("gifRate") private var rate = 10.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save as GIF").font(.headline)
            Text("Starts at the playhead (\(timeLabel(start))) and loops. GIFs get big quickly, so keep them short.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("Length", selection: $length) {
                ForEach(GIFExporter.lengths, id: \.self) { Text("\(Int($0)) s").tag($0) }
            }
            Picker("Size", selection: $width) {
                ForEach(GIFExporter.sizes, id: \.width) { Text("\($0.name) (\($0.width) px)").tag($0.width) }
            }
            Picker("Smoothness", selection: $rate) {
                ForEach(GIFExporter.rates, id: \.self) { Text("\(Int($0)) frames a second").tag($0) }
            }
            HStack {
                Spacer()
                Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
                Button("Save…") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width: 340)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = take.files.baseName + ".gif"
        panel.canCreateDirectories = true
        close()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        RecorderModel.current?.exportGIF(of: take, start: start, length: length, width: width, fps: rate, to: url)
    }
}
