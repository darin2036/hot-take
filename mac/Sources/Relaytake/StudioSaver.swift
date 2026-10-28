import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import Foundation
import RelaytakeCore

/// How a Studio edit is written out.
struct StudioSaveOptions {
    /// nil keeps the render's own quality. Otherwise the file is compressed to these settings.
    var quality: EncodingSettings?
    var includeAudio = true
}

/// Turns a Studio project into a file. Text, music and voiceover are drawn and mixed once, at full
/// quality, by the Studio's own renderer. If the result should also be smaller, or a different
/// format, that render is handed to the app's existing compressor and exporter, which only ever see a
/// finished video, so they need no knowledge of overlays or extra audio.
enum StudioSaver {
    static func render(
        asset: AVAsset, project: StudioProject, to destination: URL, format: VideoExportFormat,
        options: StudioSaveOptions, progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        let fileManager = FileManager.default
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".relaytake-studio-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let direct = format != .webm && options.quality == nil
        // Direct saves are MP4 or MOV as asked; two-step saves use an MP4 master.
        let masterExtension = direct ? format.rawValue : "mp4"
        let master = staging.appendingPathComponent("master.\(masterExtension)")
        let share = direct ? 1.0 : 0.5

        try await StudioComposer.export(asset: asset, project: project, to: master, includeAudio: options.includeAudio) { value in
            Task { @MainActor in progress(value * share) }
        }
        try Task.checkCancellation()

        if direct {
            try place(master, at: destination)
        } else {
            let masterAsset = AVURLAsset(url: master)
            let length = try await masterAsset.load(.duration).seconds
            // WebM with no size chosen uses the Large preset, since the encoder needs a bit rate.
            let encoding = options.quality ?? EncodingPreferences.resolve(.large)
            try await VideoExport.save(
                asset: masterAsset, segments: [TimeSpan(start: 0, end: length)], to: destination, format: format,
                quality: encoding, includeAudio: options.includeAudio
            ) { value in progress(0.5 + value * 0.5) }
        }
        await progress(1)
    }

    /// Moves a finished file into place, replacing what the user agreed to replace.
    private static func place(_ file: URL, at destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: file)
        } else {
            try FileManager.default.moveItem(at: file, to: destination)
        }
    }
}

/// What the Studio's Share button sends: the edited video, drawn only once the person picks where to send it.
struct EditedVideo: Transferable {
    let render: @Sendable () async throws -> URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mpeg4Movie) { video in
            SentTransferredFile(try await video.render())
        }
    }
}

/// Share in the toolbar while the Studio is open. With edits (cuts, text, voiceover…) it shares the edited
/// version; with none it shares the recording as it is.
struct StudioShareButton: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        HStack(spacing: 4) { shareLink; projectButton }
    }

    /// One `.hottake` file with the recording and the edit, for a teammate to open and carry on.
    private var projectButton: some View {
        Button { model.shareProject() } label: { Label("Save Project", systemImage: "shippingbox") }
            .help("Save the recording and your edit as one Hot Take file a teammate can open and keep editing")
            .disabled(!model.ready || model.saveProgress != nil)
    }

    private var shareLink: some View {
        Group {
            if model.hasUnsavedChanges {
                ShareLink(
                    item: EditedVideo { try await model.renderForSharing() },
                    preview: SharePreview(model.take.title)
                ) { Label("Share", systemImage: "square.and.arrow.up") }
                    .help("Share the video with your Studio edits. Your original is not changed.")
            } else {
                ShareLink(item: model.take.files.video) { Label("Share", systemImage: "square.and.arrow.up") }
                    .help("Share this recording")
            }
        }
        .disabled(!model.ready || model.saveProgress != nil)
    }
}
