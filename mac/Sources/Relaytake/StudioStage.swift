import RelaytakeCore
import SwiftUI

/// The Studio's edited preview with a play button and scrubber, for theater, pop-out and full screen
/// (where the Studio's own transport bar isn't there).
struct StudioStage: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        VStack(spacing: 0) {
            StudioPreview(model: model)
            StageControls(model: model, clock: model.clock)
        }
        .background(.black)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) { model.togglePlay(); return .handled }
    }
}

private struct StageControls: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var clock: StudioClock

    var body: some View {
        HStack(spacing: 12) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 18)
            }
            .buttonStyle(.plain)
            Slider(
                value: Binding(get: { clock.time }, set: { model.seek(to: $0) }),
                in: 0...max(model.project.outputDuration, 0.1))
            Text("\(timeLabel(clock.time)) / \(timeLabel(model.project.outputDuration))")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
