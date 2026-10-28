import AppKit
import RelaytakeCore
import SwiftUI

/// The first time Hot Take opens: a rainbow shimmer over the whole window with the logo in the middle, a plain
/// "Welcome" and "What's your Hot Take?", then it fades away into the app. A click or key press skips ahead.
struct WelcomeView: View {
    let onFinish: () -> Void

    @State private var started = Date()
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    var body: some View {
        TimelineView(.animation) { context in
            WelcomeScene(elapsed: context.date.timeIntervalSince(started), animated: !reduceMotion)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: skip)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: .down) { _ in skip(); return .handled }
        .onAppear { focused = true }
        .task {
            while !Task.isCancelled {
                if WelcomeTimeline.isFinished(at: Date().timeIntervalSince(started)) { finish(); return }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Welcome to Hot Take. What's your Hot Take?")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Skip", skip)
    }

    /// Straight to the fade-out, so skipping still ends on the same soft reveal.
    private func skip() {
        let now = Date().timeIntervalSince(started)
        let target = WelcomeTimeline.skipped(from: now)
        started = Date().addingTimeInterval(-target)
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}

/// One picture of the welcome at a given moment. Everything is a function of `elapsed`, which also lets the
/// `--welcome-snapshot` check draw any frame.
struct WelcomeScene: View {
    let elapsed: Double
    var animated = true

    private var backdrop: Double { WelcomeTimeline.backdrop(at: elapsed) }
    private var content: Double { WelcomeTimeline.content(at: elapsed) }

    var body: some View {
        ZStack {
            Shimmer(time: animated ? elapsed : 0)
                .opacity(backdrop)
            // Keeps the words readable over the brightest colors.
            RadialGradient(colors: [.black.opacity(0.2), .clear], center: .center, startRadius: 0, endRadius: 420)
                .opacity(backdrop)

            VStack(spacing: 22) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                    .scaleEffect(0.8 + 0.2 * WelcomeTimeline.logo(at: elapsed))
                    .opacity(WelcomeTimeline.logo(at: elapsed))

                VStack(spacing: 6) {
                    Text("Welcome")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .opacity(0.9 * WelcomeTimeline.greeting(at: elapsed))
                    Text("What’s your Hot Take?")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .opacity(WelcomeTimeline.question(at: elapsed))
                        .offset(y: 8 * (1 - WelcomeTimeline.question(at: elapsed)))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 2)
            }
            .opacity(content)
        }
        .ignoresSafeArea()
    }
}

/// A slowly drifting rainbow with a soft band of light that sweeps across it.
private struct Shimmer: View {
    let time: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MeshGradient(width: 3, height: 3, points: points, colors: colors)
                // The sweep: a tilted band of light that passes over every few seconds.
                let travel = (time * 0.32).truncatingRemainder(dividingBy: 1.7) - 0.35
                LinearGradient(colors: [.clear, .white.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: proxy.size.width * 0.35)
                    .rotationEffect(.degrees(18))
                    .offset(x: (travel - 0.5) * proxy.size.width * 1.4)
                    .blendMode(.overlay)
            }
            .clipped()
        }
    }

    private var points: [SIMD2<Float>] {
        func drift(_ speed: Double, _ phase: Double, _ amount: Double) -> Float { Float(sin(time * speed + phase) * amount) }
        return [
            [0, 0], [0.5 + drift(0.7, 0, 0.12), 0], [1, 0],
            [0, 0.5 + drift(0.6, 1, 0.12)], [0.5 + drift(0.5, 2, 0.16), 0.5 + drift(0.8, 3, 0.16)], [1, 0.5 + drift(0.9, 4, 0.12)],
            [0, 1], [0.5 + drift(0.65, 5, 0.12), 1], [1, 1],
        ]
    }

    /// Every hue once across the picture, turning slowly.
    private var colors: [Color] {
        (0..<9).map { index in
            let hue = (Double(index) / 9 + time * 0.06).truncatingRemainder(dividingBy: 1)
            return Color(hue: hue, saturation: 0.72, brightness: 0.96)
        }
    }
}
