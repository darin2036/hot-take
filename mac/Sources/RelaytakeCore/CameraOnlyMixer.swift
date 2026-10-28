import AVFoundation
import Foundation

/// A camera-only take is the camera's picture and the microphone's sound, recorded by two separate pieces of
/// the system that start a moment apart. This puts them in one MP4 with the sound lined up against the picture.
public enum CameraOnlyMixer {
    public enum MixError: LocalizedError {
        case noVideo
        case failed(String)
        public var errorDescription: String? {
            switch self {
            case .noVideo: "The camera did not record any picture."
            case .failed(let why): why
            }
        }
    }

    /// - Parameter audioDelay: how many seconds after the picture began the sound began. Negative when the
    ///   sound began first: its start is dropped so the two still line up.
    public static func merge(video: URL, audio: URL?, audioDelay: Double, to destination: URL) async throws {
        let videoAsset = AVURLAsset(url: video)
        guard let source = try await videoAsset.loadTracks(withMediaType: .video).first else { throw MixError.noVideo }
        let total = try await videoAsset.load(.duration)
        guard total.seconds > 0 else { throw MixError.noVideo }

        let composition = AVMutableComposition()
        if let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            track.preferredTransform = try await source.load(.preferredTransform)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: total), of: source, at: .zero)
        }
        if let audio {
            let soundAsset = AVURLAsset(url: audio)
            if let sound = try await soundAsset.loadTracks(withMediaType: .audio).first,
               let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let length = try await soundAsset.load(.duration).seconds
                let skip = max(0, -audioDelay)
                let place = max(0, audioDelay)
                let playable = min(length - skip, total.seconds - place)
                if playable > 0.05 {
                    try track.insertTimeRange(
                        CMTimeRange(start: CMTime(seconds: skip, preferredTimescale: 600), duration: CMTime(seconds: playable, preferredTimescale: 600)),
                        of: sound, at: CMTime(seconds: place, preferredTimescale: 600))
                }
            }
        }

        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".relaytake-mix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let output = staging.appendingPathComponent("mixed.mp4")
        // As recorded if the pieces fit an MP4; otherwise encoded (a sound file that is not AAC, say).
        if (try? await export(composition, preset: AVAssetExportPresetPassthrough, to: output)) == nil {
            try? FileManager.default.removeItem(at: output)
            do { try await export(composition, preset: AVAssetExportPresetHighestQuality, to: output) }
            catch { throw MixError.failed("The camera take could not be saved: \(error.localizedDescription)") }
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: output)
        } else {
            try FileManager.default.moveItem(at: output, to: destination)
        }
    }

    private static func export(_ asset: AVAsset, preset: String, to url: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw MixError.failed("This Mac cannot save the take.") }
        try await session.export(to: url, as: .mp4)
    }
}
