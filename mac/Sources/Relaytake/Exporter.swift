import AVFoundation
import Foundation
import RelaytakeCore

enum ExportError: LocalizedError {
    case unreadable
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .unreadable: "This video has no readable tracks."
        case .failed(let message): message
        }
    }
}

/// Builds and saves an edited copy from a cut list. The original file is never modified.
/// Saving re-encodes, so it is not lossless and cuts can land a few frames off.
enum Exporter {
    static func composition(for asset: AVAsset, segments: [TimeSpan]) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        var inserted = false
        for type in [AVMediaType.video, .audio] {
            // Recordings can carry separate microphone and system-audio tracks; keep every one.
            for source in try await asset.loadTracks(withMediaType: type) {
                guard let track = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid)
                else { continue }
                if type == .video { track.preferredTransform = try await source.load(.preferredTransform) }
                var cursor = CMTime.zero
                for segment in segments {
                    let range = CMTimeRange(
                        start: CMTime(seconds: segment.start, preferredTimescale: 600),
                        duration: CMTime(seconds: segment.length, preferredTimescale: 600))
                    try track.insertTimeRange(range, of: source, at: cursor)
                    cursor = cursor + range.duration
                    inserted = true
                }
            }
        }
        guard inserted else { throw ExportError.unreadable }
        return composition
    }

    static func save(
        asset: AVAsset, segments: [TimeSpan], to url: URL, quality: EncodingSettings? = nil, includeAudio: Bool = true, progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        let composition = try await composition(for: asset, segments: segments)
        if let quality {
            try await Compressor.save(asset: composition, to: url, quality: quality, includeAudio: includeAudio, progress: progress)
            return
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw ExportError.failed("This Mac cannot export this video.") }
        try? FileManager.default.removeItem(at: url)

        let watcher = Task {
            for await state in session.states(updateInterval: 0.2) {
                if case .exporting(let value) = state { await progress(value.fractionCompleted) }
            }
        }
        defer { watcher.cancel() }
        do {
            try await session.export(to: url, as: url.pathExtension.lowercased() == "mov" ? .mov : .mp4)
        } catch {
            try? FileManager.default.removeItem(at: url)  // never leave a half-written copy
            throw ExportError.failed(error.localizedDescription)
        }
    }
}
