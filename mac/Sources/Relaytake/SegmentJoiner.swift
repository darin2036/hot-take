import AVFoundation

/// Joins the pieces of a paused take end to end. Nothing is re-encoded, so it is quick even for long takes.
enum SegmentJoiner {
    static func join(_ pieces: [URL], to destination: URL, as fileType: AVFileType) async throws {
        let composition = AVMutableComposition()
        var videoTrack: AVMutableCompositionTrack?
        var audioTracks: [AVMutableCompositionTrack] = []
        var cursor = CMTime.zero
        for piece in pieces {
            let asset = AVURLAsset(url: piece)
            let duration = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: duration)
            if let source = try await asset.loadTracks(withMediaType: .video).first {
                if videoTrack == nil {
                    let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                    track?.preferredTransform = try await source.load(.preferredTransform)
                    videoTrack = track
                }
                try videoTrack?.insertTimeRange(range, of: source, at: cursor)
            }
            for (index, source) in try await asset.loadTracks(withMediaType: .audio).enumerated() {
                if index == audioTracks.count, let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    audioTracks.append(track)
                }
                if index < audioTracks.count { try audioTracks[index].insertTimeRange(range, of: source, at: cursor) }
            }
            cursor = cursor + duration
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try? FileManager.default.removeItem(at: destination)
        try await session.export(to: destination, as: fileType)
    }
}
