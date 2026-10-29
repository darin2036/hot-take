import AVFoundation
import Foundation
import Testing
@testable import RelaytakeCore

@Suite struct RecordingCueTests {
    @Test func cuesDecodeAsShortQuietAudioWithSilentEdges() throws {
        for cue in RecordingCue.allCases {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
            defer { try? FileManager.default.removeItem(at: url) }
            try cue.waveData().write(to: url)
            let file = try AVAudioFile(forReading: url)
            #expect(file.processingFormat.channelCount == 1)
            #expect(file.processingFormat.sampleRate == 44_100)
            let duration = Double(file.length) / file.processingFormat.sampleRate
            #expect(duration >= 0.1 && duration <= 0.5)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let channels = try #require(buffer.floatChannelData)
            let samples = Array(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength)))
            #expect(samples.first == 0 && samples.last == 0)
            #expect(samples.allSatisfy { $0.isFinite && abs($0) < 0.23 })
            #expect(samples.contains { abs($0) > 0.2 })
            // Avoid sharp sample discontinuities, including between the end chime's two notes.
            #expect(zip(samples, samples.dropFirst()).allSatisfy { abs($0 - $1) < 0.04 })
        }
    }
}
