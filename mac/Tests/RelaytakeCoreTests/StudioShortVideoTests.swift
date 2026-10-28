import AVFoundation
import Foundation
import Testing

@testable import RelaytakeCore

/// A screen recording's picture can stop a little before its sound does (nothing changed on screen, so no
/// later frames were written). Saving must still work, holding the last picture to the end.
@Suite(.serialized) struct StudioShortVideoTests {
    private func videoShorterThanAudio() async throws -> URL {
        let picture = AVURLAsset(url: try await TestMedia.video(seconds: 4, color: (20, 30, 120)))
        let sound = AVURLAsset(url: try TestMedia.tone(seconds: 6, frequency: 440))
        let composition = AVMutableComposition()
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
            .insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 4, preferredTimescale: 600)),
                of: try await picture.loadTracks(withMediaType: .video)[0], at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            .insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 6, preferredTimescale: 600)),
                of: try await sound.loadTracks(withMediaType: .audio)[0], at: .zero)
        let out = TestMedia.tempURL("mp4")
        let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
        try await session.export(to: out, as: .mp4)
        return out
    }

    @Test func aPictureThatEndsBeforeTheSoundStillSaves() async throws {
        let source = try await videoShorterThanAudio()
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        var project = StudioProject(duration: duration)
        project.addText(at: 1, text: "HELLO")
        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: asset, project: project, to: out) { _ in }
        #expect(FileManager.default.fileExists(atPath: out.path))
        let length = try await TestMedia.duration(of: out)
        #expect(length > 3.5, "rendered \(length) s")
    }
}
