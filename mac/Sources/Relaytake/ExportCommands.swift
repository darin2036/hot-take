import AppKit
import AVFoundation
import RelaytakeCore
import SwiftUI
import UniformTypeIdentifiers

extension LibraryModel {
    /// Prefer the open recording; otherwise require exactly one visible library selection.
    var exportTake: TakeEntry? {
        if let selected { return selected }
        let targets = visibleTakes.filter { checked.contains($0.id) }
        return targets.count == 1 ? targets.first : nil
    }

    func exportVideo(format: VideoExportFormat) {
        guard let take = exportTake, format.available else { return }
        if let studio = openStudio, studio.take.id == take.id {
            studio.export(format: format, options: .stored)
            return
        }
        guard let recorder = RecorderModel.current else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .movie]
        panel.nameFieldStringValue = take.files.baseName + "." + format.rawValue
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.standardizedFileURL.resolvingSymlinksInPath() != take.files.video.standardizedFileURL.resolvingSymlinksInPath() else {
            recorder.message = "Choose a different name to keep your original."
            return
        }
        let options = StudioSaveOptions.stored
        recorder.runExclusively("Exporting…") {
            do {
                let asset = AVURLAsset(url: take.files.video)
                let duration = try await asset.load(.duration).seconds
                let notes = TakeLibrary.metadata(for: take.files)
                let shown = (notes?.chaptersEnabled ?? Pref.chaptersByDefault) ? notes?.chapters ?? [] : []
                try await StudioSaver.render(
                    asset: asset, project: StudioProject(duration: duration), to: url,
                    format: format, options: options, chapters: shown
                ) { value in
                    recorder.phase = .processing("Exporting… \(Int(value * 100))%")
                }
                recorder.notice = "Exported “\(url.lastPathComponent)”."
                recorder.noticeFile = url
            } catch {
                recorder.message = "Could not export: \(error.localizedDescription)"
            }
        }
    }

    /// File ▸ Export ▸ Transcript as Markdown…
    func exportTranscriptMarkdown() {
        guard let take = exportTake else { return }
        let metadata = TakeLibrary.metadata(for: take.files)
        guard let metadata, !metadata.transcript.isEmpty else {
            RecorderModel.current?.message = "“\(take.title)” has no transcript yet. Open it and choose Make Transcript first."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = take.files.baseName + ".md"
        panel.canCreateDirectories = true
        panel.message = "Saves the transcript as a Markdown file, with its summary and chapters."
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = TranscriptMarkdown.markdown(
            title: take.title, created: metadata.created, duration: metadata.durationSeconds, summary: metadata.summary,
            tags: metadata.tags, transcript: metadata.transcript, chapters: metadata.chaptersEnabled == false ? [] : metadata.chapters)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            RecorderModel.current?.notice = "Exported “\(url.lastPathComponent)”."
            RecorderModel.current?.noticeFile = url
        } catch {
            RecorderModel.current?.message = "Could not export the transcript: \(error.localizedDescription)"
        }
    }
}
