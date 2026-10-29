import AVFoundation

/// Joins the pieces of a paused take end to end. Nothing is re-encoded, so it is quick even for long takes.
/// `lastLength` cuts the last piece short, which is how a rewind shortens a piece.
enum SegmentJoiner {
    static func join(_ pieces: [URL], to destination: URL, as fileType: AVFileType, lastLength: Double? = nil) async throws {
        let composition = AVMutableComposition()
        var videoTrack: AVMutableCompositionTrack?
        var audioTracks: [AVMutableCompositionTrack] = []
        var cursor = CMTime.zero
        for (index, piece) in pieces.enumerated() {
            let asset = AVURLAsset(url: piece)
            var duration = try await asset.load(.duration)
            if index == pieces.count - 1, let lastLength, lastLength < duration.seconds {
                duration = CMTime(seconds: lastLength, preferredTimescale: 600)
            }
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

    /// Cuts a piece down to its first `length` seconds, in place. The file is only replaced once the cut one is written.
    static func trim(_ piece: URL, to length: Double, as fileType: AVFileType) async throws {
        let staging = piece.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).\(piece.pathExtension)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try await join([piece], to: staging, as: fileType, lastLength: length)
        _ = try FileManager.default.replaceItemAt(piece, withItemAt: staging)
    }

    /// How long a piece is, in seconds, or 0 if it cannot be read.
    static func length(of piece: URL) async -> Double {
        guard FileManager.default.fileExists(atPath: piece.path),
              let duration = try? await AVURLAsset(url: piece).load(.duration), duration.isNumeric else { return 0 }
        return max(0, duration.seconds)
    }
}
