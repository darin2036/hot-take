import AVFoundation
import Foundation
import RelaytakeCore

@MainActor
final class PlayerModel: ObservableObject {
    let player = AVPlayer()
    @Published var time: Double = 0
    @Published var duration: Double = 0

    private var observer: Any?
    private var url: URL?

    init() {
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { [weak self] value in
            MainActor.assumeIsolated { self?.time = value.seconds }
        }
    }

    deinit {
        if let observer { player.removeTimeObserver(observer) }
        player.pause()
    }

    func load(_ url: URL) async {
        self.url = url
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        time = 0
        duration = (try? await item.asset.load(.duration).seconds) ?? 0
    }

    func seek(to seconds: Double) {
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        time = target.seconds  // so a paused player still shows where it is
    }

    func play(from seconds: Double) {
        seek(to: seconds)
        player.play()
    }

    func togglePlay() {
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
    }
}
