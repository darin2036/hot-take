import Foundation

/// Original, locally synthesized cues; no sampled audio or external assets. MIT licensed.
public enum RecordingCue: CaseIterable {
    case count, lastCount, ended

    /// Mono 16-bit PCM WAV, with soft edges to avoid clicks.
    public func waveData() -> Data {
        let rate = 44_100
        let notes: [(frequency: Double, duration: Double)]
        switch self {
        case .count: notes = [(660, 0.12)]
        case .lastCount: notes = [(880, 0.18)]
        case .ended: notes = [(880, 0.16), (660, 0.24)]
        }
        var samples = Data()
        for note in notes {
            let frames = Int(note.duration * Double(rate))
            for frame in 0..<frames {
                let time = Double(frame) / Double(rate)
                let edge = min(1, min(Double(frame), Double(frames - 1 - frame)) / (0.012 * Double(rate)))
                let envelope = 0.5 - 0.5 * cos(.pi * edge)
                let tone = sin(2 * .pi * note.frequency * time)
                let sample = Int16((tone * envelope * 0.22 * Double(Int16.max)).rounded())
                samples.appendLE(UInt16(bitPattern: sample))
            }
        }
        var data = Data("RIFF".utf8)
        data.appendLE(UInt32(36 + samples.count))
        data.append(Data("WAVEfmt ".utf8))
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1)) // PCM
        data.appendLE(UInt16(1)) // mono
        data.appendLE(UInt32(rate))
        data.appendLE(UInt32(rate * 2))
        data.appendLE(UInt16(2))
        data.appendLE(UInt16(16))
        data.append(Data("data".utf8))
        data.appendLE(UInt32(samples.count))
        data.append(samples)
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
