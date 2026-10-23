import AVFoundation
import Foundation

/// Loudness over time, measured from the audio itself. This is what finds quiet parts: a language
/// model cannot hear, but a few lines of arithmetic can.
enum AudioLevels {
    static let windowSeconds = 0.1
    private static let sampleRate = 16_000.0

    /// RMS level in dBFS for each 0.1 s window, mixing every audio track (microphone and system sound).
    /// Empty when the file has no audio.
    static func analyze(url: URL) async throws -> [Double] {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard !tracks.isEmpty else { return [] }

            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: sampleRate,
            ])
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? ExportError.unreadable }

            let perWindow = Int(sampleRate * windowSeconds)
            var levels: [Double] = []
            var sumSquares = 0.0
            var count = 0
            while let buffer = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
                let length = CMBlockBufferGetDataLength(block)
                var samples = [Int16](repeating: 0, count: length / 2)
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &samples)
                for sample in samples {
                    let value = Double(sample) / 32768
                    sumSquares += value * value
                    count += 1
                    if count == perWindow {
                        levels.append(decibels(sumSquares / Double(count)))
                        sumSquares = 0
                        count = 0
                    }
                }
            }
            if count > perWindow / 2 { levels.append(decibels(sumSquares / Double(count))) }
            if reader.status == .failed { throw reader.error ?? ExportError.unreadable }
            return levels
        }.value
    }

    private static func decibels(_ meanSquare: Double) -> Double {
        meanSquare > 0 ? 10 * log10(meanSquare) : -120
    }
}
