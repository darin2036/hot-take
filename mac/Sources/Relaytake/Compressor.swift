import AVFoundation
import Foundation
import RelaytakeCore

/// Bounded reader/writer transcode: H.264 + AAC, no upscaling, original is read-only.
enum Compressor {
    static func save(asset: AVAsset, to url: URL, quality: EncodingSettings, includeAudio: Bool = true,
                     progress: @escaping @MainActor (Double) -> Void) async throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw ExportError.failed("Choose a new output filename.") }
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: url, fileType: url.pathExtension.lowercased() == "mov" ? .mov : .mp4)
        writer.shouldOptimizeForNetworkUse = true
        var completed = false
        defer { if !completed { reader.cancelReading(); writer.cancelWriting(); try? FileManager.default.removeItem(at: url) } }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ExportError.unreadable }
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, duration.seconds > 0 else { throw ExportError.unreadable }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        let size = quality.dimensions(width: abs(rect.width), height: abs(rect.height))
        let sourceFPS = Double(try await track.load(.nominalFrameRate))
        let fps = sourceFPS > 0 ? min(Double(quality.fps), sourceFPS) : Double(quality.fps)
        var composition = AVVideoComposition.Configuration()
        composition.renderSize = CGSize(width: size.width, height: size.height)
        composition.frameDuration = CMTime(seconds: 1 / fps, preferredTimescale: 60_000)
        var instruction = AVVideoCompositionInstruction.Configuration()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        var layer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: track)
        let scaled = transform.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .concatenating(CGAffineTransform(scaleX: Double(size.width) / abs(rect.width), y: Double(size.height) / abs(rect.height)))
        layer.setTransform(scaled, at: .zero)
        instruction.layerInstructions = [AVVideoCompositionLayerInstruction(configuration: layer)]
        composition.instructions = [AVVideoCompositionInstruction(configuration: instruction)]
        let builtComposition = AVVideoComposition(configuration: composition)
        let videoOut = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        videoOut.videoComposition = builtComposition; videoOut.alwaysCopiesSampleData = false
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: quality.videoBitrate,
                AVVideoExpectedSourceFrameRateKey: fps, AVVideoMaxKeyFrameIntervalKey: Int(fps * 2),
                // Offline export can use inter-frame prediction without live-capture latency constraints.
                AVVideoAllowFrameReorderingKey: true,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
        guard reader.canAdd(videoOut), writer.canAdd(videoIn) else { throw ExportError.unreadable }
        reader.add(videoOut); writer.add(videoIn)
        var audioPair: (AVAssetReaderOutput, AVAssetWriterInput)?
        let audioTracks = includeAudio ? try await asset.loadTracks(withMediaType: .audio) : []
        if !audioTracks.isEmpty {
            let audioOut = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: quality.channels,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false])
            audioOut.alwaysCopiesSampleData = false
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioTracks.map { track in
                let p = AVMutableAudioMixInputParameters(track: track)
                p.setVolume(1 / Float(audioTracks.count), at: .zero); return p
            }
            audioOut.audioMix = mix
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000, AVNumberOfChannelsKey: quality.channels, AVEncoderBitRateKey: quality.audioBitrate])
            guard reader.canAdd(audioOut), writer.canAdd(audioIn) else { throw ExportError.unreadable }
            reader.add(audioOut); writer.add(audioIn); audioPair = (audioOut, audioIn)
        }
        guard writer.startWriting(), reader.startReading() else { throw ExportError.failed(reader.error?.localizedDescription ?? writer.error?.localizedDescription ?? "Could not start compression.") }
        writer.startSession(atSourceTime: .zero)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await pump(videoOut, into: videoIn, writer: writer) { time in await progress(min(0.99, time / duration.seconds)) } }
            if let (output, input) = audioPair { group.addTask { try await pump(output, into: input, writer: writer) { _ in } } }
            try await group.waitForAll()
        }
        try Task.checkCancellation()
        guard reader.status == .completed else { throw ExportError.failed(reader.error?.localizedDescription ?? "Could not read the full video.") }
        await writer.finishWriting()
        try Task.checkCancellation()
        guard writer.status == .completed else { throw ExportError.failed(writer.error?.localizedDescription ?? "Could not finish compression.") }
        completed = true; await progress(1)
    }

    private static func pump(_ output: AVAssetReaderOutput, into input: AVAssetWriterInput, writer: AVAssetWriter,
                             report: (Double) async -> Void) async throws {
        var lastReport = -1.0
        while true {
            try Task.checkCancellation()
            guard writer.status == .writing else { throw ExportError.failed(writer.error?.localizedDescription ?? "Encoding stopped.") }
            if !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)); continue }
            // One sample at a time; CoreMedia buffers are released before the next iteration.
            guard let sample = output.copyNextSampleBuffer() else { input.markAsFinished(); return }
            guard input.append(sample) else { throw ExportError.failed(writer.error?.localizedDescription ?? "Could not encode a frame.") }
            let time = sample.presentationTimeStamp.seconds
            if time - lastReport > 0.2 { await report(time); lastReport = time }
        }
    }
}
