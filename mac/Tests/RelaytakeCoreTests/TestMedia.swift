import AVFoundation
import CoreGraphics
import Foundation

/// Generates tiny media files and measures rendered output, so rendering is tested for real.
enum TestMedia {
    static func tempURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("relaytake-test-\(UUID().uuidString).\(ext)")
    }

    /// A sine tone as a .caf file. `amplitude` is peak, 0...1.
    static func tone(seconds: Double, frequency: Double, amplitude: Double = 0.5) throws -> URL {
        let url = tempURL("caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            buffer.floatChannelData![0][index] = Float(amplitude * sin(2 * .pi * frequency * Double(index) / 44_100))
        }
        try file.write(from: buffer)
        return url
    }

    /// A solid-color H.264 video, optionally with a tone as its sound.
    static func video(seconds: Double, color: (UInt8, UInt8, UInt8), toneHz: Double? = nil) async throws -> URL {
        let width = 320, height = 180, fps = 15
        let silent = tempURL("mp4")
        let writer = try AVAssetWriter(outputURL: silent, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<Int(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = buffer!
            CVPixelBufferLockBaseAddress(pixels, [])
            let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
            for row in 0..<height {
                for column in 0..<width {
                    let offset = row * rowBytes + column * 4
                    base[offset] = color.2; base[offset + 1] = color.1; base[offset + 2] = color.0; base[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard let toneHz else { return silent }

        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: silent)
        let length = CMTime(seconds: seconds, preferredTimescale: 600)
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
            .insertTimeRange(CMTimeRange(start: .zero, duration: length), of: try await videoAsset.loadTracks(withMediaType: .video)[0], at: .zero)
        let toneAsset = AVURLAsset(url: try tone(seconds: seconds, frequency: toneHz))
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            .insertTimeRange(CMTimeRange(start: .zero, duration: length), of: try await toneAsset.loadTracks(withMediaType: .audio)[0], at: .zero)
        let out = tempURL("mp4")
        let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
        try await session.export(to: out, as: .mp4)
        return out
    }

    /// RMS loudness (0...1) of the sound between two times.
    static func rms(of url: URL, from: Double, to: Double) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return 0 }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600), end: CMTime(seconds: to, preferredTimescale: 600))
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: 16_000,
        ])
        reader.add(output)
        reader.startReading()
        var sum = 0.0, count = 0
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var samples = [Int16](repeating: 0, count: length / 2)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &samples)
            for sample in samples { let value = Double(sample) / 32768; sum += value * value; count += 1 }
        }
        return count == 0 ? 0 : (sum / Double(count)).squareRoot()
    }

    /// Mean brightness (0...255) of a region of the picture at `time`. `region` is normalised, top-left origin.
    static func brightness(of url: URL, at time: Double, region: CGRect) async throws -> Double {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
        return brightness(of: image, region: region)
    }

    static func brightness(of image: CGImage, region: CGRect) -> Double {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Memory row 0 is the top of the picture.
        let x0 = Int(region.minX * Double(width)), x1 = max(x0 + 1, Int(region.maxX * Double(width)))
        let y0 = Int(region.minY * Double(height)), y1 = max(y0 + 1, Int(region.maxY * Double(height)))
        var total = 0.0, samples = 0.0
        for row in y0..<min(y1, height) {
            for column in x0..<min(x1, width) {
                let offset = (row * width + column) * 4
                total += (Double(data[offset]) + Double(data[offset + 1]) + Double(data[offset + 2])) / 3
                samples += 1
            }
        }
        return total / max(samples, 1)
    }

    /// Mean red, green and blue (0...255) of a region of the picture at `time`.
    static func channels(of url: URL, at time: Double, region: CGRect) async throws -> (red: Double, green: Double, blue: Double) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let x0 = Int(region.minX * Double(width)), x1 = max(x0 + 1, Int(region.maxX * Double(width)))
        let y0 = Int(region.minY * Double(height)), y1 = max(y0 + 1, Int(region.maxY * Double(height)))
        var sums = (0.0, 0.0, 0.0), count = 0.0
        for row in y0..<min(y1, height) {
            for column in x0..<min(x1, width) {
                let offset = (row * width + column) * 4
                sums.0 += Double(data[offset]); sums.1 += Double(data[offset + 1]); sums.2 += Double(data[offset + 2]); count += 1
            }
        }
        return (sums.0 / count, sums.1 / count, sums.2 / count)
    }

    static func duration(of url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }
}
