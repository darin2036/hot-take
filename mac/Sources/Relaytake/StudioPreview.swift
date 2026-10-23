import AppKit
import AVKit
import RelaytakeCore
import SwiftUI

/// The player with no controls of its own (the Studio has a transport bar).
struct StudioPlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.allowsMagnification = false
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

extension TextColor {
    var color: Color { Color(nsColor: nsColor) }
    init(_ color: Color) { self.init(NSColor(color)) }
}

/// The edited video with its text on top. Text is sized and placed the same way as in the saved
/// file (a fraction of the picture's height, centered on x/y), and can be dragged into place.
struct StudioPreview: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        GeometryReader { geometry in
            let frame = fitted(model.videoSize, in: geometry.size)
            ZStack {
                Color.black
                StudioPlayerSurface(player: model.player)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)

                // The camera bubble can be dragged anywhere in the picture. The outline follows the pointer; the
                // picture itself redraws once it is dropped.
                if model.project.cameraSource != nil, model.project.camera.isVisible {
                    let bubble = model.project.camera.frame(in: model.videoSize)
                    let scale = frame.width / max(model.videoSize.width, 1)
                    CameraDragHandle(shape: model.project.camera.shape)
                        .frame(width: bubble.width * scale, height: bubble.height * scale)
                        .position(x: frame.minX + bubble.midX * scale, y: frame.minY + bubble.midY * scale)
                        .gesture(
                            DragGesture(minimumDistance: 2, coordinateSpace: .named("preview"))
                                .onChanged { value in
                                    model.beginGestureIfNeeded()
                                    let x = (value.location.x - frame.minX) / max(frame.width, 1)
                                    let y = (value.location.y - frame.minY) / max(frame.height, 1)
                                    model.live { $0.camera.move(toX: x, y: y) }
                                }
                                .onEnded { _ in model.endGesture() }
                        )
                        .help("Drag to move the camera")
                }

                // With a zoom selected, a click on the picture points the zoom at that spot.
                if case .zoom(let id) = model.selection {
                    Color.clear.contentShape(Rectangle())
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .onTapGesture(coordinateSpace: .named("preview")) { location in
                            let shown = CGPoint(
                                x: min(1, max(0, (location.x - frame.minX) / max(frame.width, 1))),
                                y: min(1, max(0, (location.y - frame.minY) / max(frame.height, 1))))
                            model.aimZoom(id, atShown: shown)
                        }
                        .help("Click to point the zoom here")
                }

                ForEach(model.project.texts) { text in
                    OverlayText(text: text, frame: frame, clock: model.clock, selected: model.selection == .text(text.id), model: model)
                }
                ForEach(model.project.captionOverlays()) { line in
                    OverlayText(text: line, frame: frame, clock: model.clock, selected: false, model: model, interactive: false)
                }

                status
            }
            .coordinateSpace(name: "preview")
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder private var status: some View {
        switch model.voice {
        case .countdown(let remaining):
            VStack(spacing: 6) {
                Text("\(remaining)").font(.system(size: 84, weight: .bold, design: .rounded))
                Text("Get ready to talk").font(.headline)
            }
            .foregroundStyle(.white)
            .padding(28)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
        case .recording:
            VStack {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 10, height: 10)
                    Text("Recording voiceover").font(.callout.weight(.semibold))
                    ProgressView(value: model.inputLevel).frame(width: 80).tint(.green)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.black.opacity(0.65), in: Capsule())
                Spacer()
            }
            .padding(10)
        case .idle:
            EmptyView()
        }
    }

    private func fitted(_ video: CGSize, in container: CGSize) -> CGRect {
        guard container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / video.width, container.height / video.height)
        let size = CGSize(width: video.width * scale, height: video.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2, width: size.width, height: size.height)
    }
}

private struct OverlayText: View {
    let text: TextOverlay
    let frame: CGRect
    @ObservedObject var clock: StudioClock
    let selected: Bool
    @ObservedObject var model: StudioModel
    /// Captions are not dragged or selected; they follow the speech.
    var interactive = true

    var body: some View {
        let fontSize = frame.height * text.heightFraction
        let opacity = text.opacity(at: clock.time)
        Text(text.text.isEmpty ? " " : text.text)
            .font(Font(text.nsFont(pointSize: fontSize) as CTFont))
            .foregroundStyle(text.color.color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: frame.width * 0.8)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, text.showsBackground ? fontSize * 0.4 : fontSize * 0.2)
            .padding(.vertical, text.showsBackground ? fontSize * 0.24 : fontSize * 0.1)
            .background {
                if text.showsBackground { RoundedRectangle(cornerRadius: fontSize * 0.35).fill(text.boxColor.color.opacity(0.6)) }
            }
            .shadow(color: text.showsBackground ? .clear : .black.opacity(0.85), radius: fontSize * 0.12)
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3])) }
            }
            .opacity(opacity)
            .allowsHitTesting(interactive && opacity > 0.05)
            .position(x: frame.minX + text.x * frame.width, y: frame.minY + text.y * frame.height)
            .onTapGesture { model.select(.text(text.id)) }
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named("preview"))
                    .onChanged { value in
                        if model.selection != .text(text.id) { model.selection = .text(text.id) }
                        if value.translation == .zero { return }
                        model.beginGestureIfNeeded()
                        let x = (value.location.x - frame.minX) / max(frame.width, 1)
                        let y = (value.location.y - frame.minY) / max(frame.height, 1)
                        model.live { $0.updateText(text.id) { $0.x = x; $0.y = y } }
                    }
                    .onEnded { _ in model.endGesture() },
                including: interactive ? .all : .none
            )
    }
}

/// A thin outline over the camera bubble that can be grabbed. (The bubble itself is drawn into the video.)
private struct CameraDragHandle: View {
    let shape: CameraShape
    @State private var hovering = false

    var body: some View {
        Group {
            if shape == .circle {
                Circle().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .background(Circle().fill(Color.clear))
            } else {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            }
        }
        .opacity(hovering ? 1 : 0.0)
        .contentShape(shape == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 14)))
        .onHover { hovering = $0 }
    }
}
