import AVFoundation
import RelaytakeCore

@MainActor
final class RecordingSounds {
    static let shared = RecordingSounds()
    private var player: AVAudioPlayer?

    func play(_ cue: RecordingCue) {
        stop()
        guard UserDefaults.standard.object(forKey: Pref.recordingSounds) as? Bool ?? true else { return }
        // Sound is optional: an unavailable output must never block recording.
        player = try? AVAudioPlayer(data: cue.waveData(), fileTypeHint: AVFileType.wav.rawValue)
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
