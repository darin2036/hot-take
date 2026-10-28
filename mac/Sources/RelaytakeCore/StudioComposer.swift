import AVFoundation
import AppKit
import Foundation

public enum StudioRenderError: LocalizedError {
    case noVideo
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .noVideo: "This recording has no video to edit."
        case .failed(let message): message
        }
    }
}

/// Builds what the Studio previews and saves: the kept pieces of the picture, the recording's own
/// sound, background music and voiceover mixed at their volumes, and (when saving) text drawn into
/// the picture. The original file is only ever read.
public enum StudioComposer {
    public struct Output {
        public let composition: AVMutableComposition
        public let audioMix: AVAudioMix?
        /// Present only when text must be drawn into the frames (saving).
        public let videoComposition: AVVideoComposition?
        public let renderSize: CGSize
    }

    private static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    /// - Parameters:
    ///   - burnText: draw the text overlays into the picture (saving). Previews draw them on top instead.
    ///   - muteOriginal: silence the recording's own sound (used while recording a voiceover).
    ///   - includeAudio: false leaves every audio track out (a silent copy).
    public static func build(
        asset: AVAsset, project: StudioProject, burnText: Bool, muteOriginal: Bool = false, includeAudio: Bool = true
    ) async throws -> Output {
        let composition = AVMutableComposition()
        var parameters: [AVMutableAudioMixInputParameters] = []
        let total = project.outputDuration

        // Picture and the recording's own sound: the kept pieces, end to end.
        var renderSize = CGSize.zero
        var addedVideo = false
        for source in try await asset.loadTracks(withMediaType: .video) {
            guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            track.preferredTransform = try await source.load(.preferredTransform)
            if !addedVideo {
                let natural = try await source.load(.naturalSize)
                let rect = CGRect(origin: .zero, size: natural).applying(track.preferredTransform)
                renderSize = CGSize(width: abs(rect.width), height: abs(rect.height))
            }
            var cursor = CMTime.zero
            for segment in project.cuts.segments {
                let range = CMTimeRange(start: time(segment.start), duration: time(segment.length))
                try track.insertTimeRange(range, of: source, at: cursor)
                cursor = cursor + range.duration
            }
            addedVideo = true
        }
        guard addedVideo else { throw StudioRenderError.noVideo }

        let originalVolume = muteOriginal ? 0 : Float(project.originalVolume)
        for source in includeAudio ? try await asset.loadTracks(withMediaType: .audio) : [] {
            guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            // Following the video's cuts, or cut on its own (the parts may leave silence between them).
            for part in project.originalAudioParts {
                let length = min(part.length, total - part.start)
                guard length > 0 else { continue }
                try track.insertTimeRange(CMTimeRange(start: time(part.source.start), duration: time(length)), of: source, at: time(part.start))
            }
            let input = AVMutableAudioMixInputParameters(track: track)
            input.setVolume(originalVolume, at: .zero)
            parameters.append(input)
        }

        // Background music and voiceover, each on its own track so volumes and fades are independent.
        for clip in project.clips where includeAudio {
            let pieces = clip.pieces(outputDuration: total)
            guard !pieces.isEmpty else { continue }
            let file = AVURLAsset(url: clip.url)
            guard let source = try await file.loadTracks(withMediaType: .audio).first,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            for piece in pieces {
                try track.insertTimeRange(
                    CMTimeRange(start: time(piece.sourceStart), duration: time(piece.length)), of: source, at: time(piece.outputStart))
            }
            let input = AVMutableAudioMixInputParameters(track: track)
            input.setVolume(Float(clip.volume), at: .zero)
            for ramp in clip.ramps(outputDuration: total) {
                input.setVolumeRamp(
                    fromStartVolume: Float(ramp.from), toEndVolume: Float(ramp.to),
                    timeRange: CMTimeRange(start: time(ramp.start), end: time(ramp.end)))
            }
            parameters.append(input)
        }

        var audioMix: AVAudioMix?
        if !parameters.isEmpty {
            let mix = AVMutableAudioMix()
            mix.inputParameters = parameters
            audioMix = mix
        }

        // The camera, laid alongside the picture on a track of its own, cut the same way.
        var camera: (id: CMPersistentTrackID, transform: CGAffineTransform, intervals: [ClosedRange<Double>])?
        if let source = project.cameraSource, project.camera.isVisible {
            let footage = AVURLAsset(url: source.url)
            if let cameraTrack = try await footage.loadTracks(withMediaType: .video).first,
               let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let length = try await footage.load(.duration).seconds
                let pieces = CameraTimeline.pieces(
                    for: project.cuts.segments, offset: source.offset, nudge: project.camera.nudge, cameraDuration: length)
                var cursor = CMTime.zero
                var intervals: [ClosedRange<Double>] = []
                for (segment, piece) in zip(project.cuts.segments, pieces) {
                    if let piece {
                        try track.insertTimeRange(
                            CMTimeRange(start: time(piece.cameraStart), duration: time(piece.length)), of: cameraTrack,
                            at: cursor + time(piece.delay))
                        let begin = cursor.seconds + piece.delay
                        intervals.append(begin...(begin + piece.length))
                    }
                    cursor = cursor + time(segment.length)
                }
                camera = (track.trackID, try await cameraTrack.load(.preferredTransform), intervals)
            }
        }

        var videoComposition: AVVideoComposition?
        let drawn = burnText ? project.texts + project.captionOverlays() : []
        // The backdrop and zoom change the picture itself, so the preview shows them too; text is drawn
        // over the preview by the Studio instead.
        let styled = project.background != nil || !project.zooms.isEmpty
        if !drawn.isEmpty || styled || camera != nil, let videoTrack = try await composition.loadTracks(withMediaType: .video).first {
            // Text is drawn into each frame by our own compositor. (the system's Core Animation video tool
            // returned blank frames on the test Mac, so it is not used.)
            let frameDuration = try await videoTrack.load(.minFrameDuration)
            let video = AVMutableVideoComposition()
            video.renderSize = renderSize
            video.frameDuration = frameDuration.isValid && frameDuration.seconds > 0 ? frameDuration : CMTime(value: 1, timescale: 30)
            video.customVideoCompositorClass = StudioCompositor.self
            video.instructions = [
                StudioInstruction(
                    timeRange: CMTimeRange(start: .zero, duration: composition.duration), trackID: videoTrack.trackID,
                    transform: videoTrack.preferredTransform,
                    overlays: drawn.compactMap { TextRenderer.render($0, renderSize: renderSize) },
                    effects: styled
                        ? CanvasEffects(canvas: renderSize, source: renderSize, background: project.background, zooms: project.zooms)
                        : nil,
                    camera: camera.map {
                        CameraEffect(
                            trackID: $0.id, transform: $0.transform, canvas: renderSize, bubble: project.camera,
                            intervals: $0.intervals)
                    })
            ]
            videoComposition = video
        }

        return Output(composition: composition, audioMix: audioMix, videoComposition: videoComposition, renderSize: renderSize)
    }

    /// Renders the project to `url` (MP4, or MOV when the name ends in .mov). An existing file at `url`
    /// is replaced; a failed or canceled export leaves nothing behind.
    public static func export(
        asset: AVAsset, project: StudioProject, to url: URL, includeAudio: Bool = true,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let output = try await build(asset: asset, project: project, burnText: true, includeAudio: includeAudio)
        guard let session = AVAssetExportSession(asset: output.composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw StudioRenderError.failed("This Mac cannot export this video.") }
        session.audioMix = output.audioMix
        session.videoComposition = output.videoComposition
        try? FileManager.default.removeItem(at: url)

        let watcher = Task {
            for await state in session.states(updateInterval: 0.2) {
                if case .exporting(let value) = state { progress(value.fractionCompleted) }
            }
        }
        defer { watcher.cancel() }
        do {
            try await session.export(to: url, as: url.pathExtension.lowercased() == "mov" ? .mov : .mp4)
        } catch {
            try? FileManager.default.removeItem(at: url)
            if error is CancellationError { throw error }
            throw StudioRenderError.failed(error.localizedDescription)
        }
    }
}
