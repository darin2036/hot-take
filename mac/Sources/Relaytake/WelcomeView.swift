import AppKit
import RelaytakeCore
import SwiftUI

/// Whether the welcome has already played since the app launched, so reopening the library window does not replay it.
enum WelcomeLaunch {
    @MainActor static var played = false
}

/// A brief illuminated title sequence at launch. A click or key press skips to the library.
struct WelcomeView: View {
    let onFinish: () -> Void

    @State private var started = Date()
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
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

/// A deterministic frame of the welcome, also used by `--welcome-snapshot`.
struct WelcomeScene: View {
    let elapsed: Double
    var animated = true

    private var backdrop: Double { WelcomeTimeline.backdrop(at: elapsed) }
    private var content: Double { WelcomeTimeline.content(at: elapsed) }
    // Reduce Motion presents the finished composition immediately, with only the exit crossfade.
    private var reveal: Double { animated ? elapsed : 4 }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 1000, proxy.size.height / 680)
            ZStack {
                WelcomeLightField(time: animated ? elapsed : 2.8)
                    .opacity(backdrop)

                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(RadialGradient(
                                colors: [Color(red: 0.43, green: 0.28, blue: 1).opacity(0.3), .clear],
                                center: .center, startRadius: 24, endRadius: 120))
                            .frame(width: 240, height: 240)
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 132, height: 132)
                            .shadow(color: .black.opacity(0.45), radius: 22, y: 14)
                    }
                    .frame(height: 156)
                    .scaleEffect(0.88 + 0.12 * WelcomeTimeline.logo(at: reveal))
                    .opacity(WelcomeTimeline.logo(at: reveal))

                    Text("WELCOME TO HOT TAKE")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(3.5)
                        .foregroundStyle(Color(red: 0.72, green: 0.69, blue: 0.89))
                        .padding(.top, 27)
                        .opacity(WelcomeTimeline.greeting(at: reveal))

                    VStack(spacing: -2) {
                        Text("What’s your")
                            .foregroundStyle(Color.white.opacity(0.95))
                        Text("Hot Take?")
                            .foregroundStyle(LinearGradient(
                                colors: [Color(red: 0.75, green: 0.73, blue: 1),
                                         Color(red: 0.65, green: 0.52, blue: 1),
                                         Color(red: 1, green: 0.66, blue: 0.74)],
                                startPoint: .leading, endPoint: .trailing))
                    }
                    .font(.system(size: 66, weight: .bold))
                    .tracking(-2.5)
                    .fixedSize()
                    .padding(.top, 16)
                    .opacity(WelcomeTimeline.question(at: reveal))
                    .offset(y: animated ? 12 * (1 - WelcomeTimeline.question(at: reveal)) : 0)

                    Text("Show it. Say it. Keep it yours.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color(red: 0.64, green: 0.63, blue: 0.74))
                        .padding(.top, 20)
                        .opacity(WelcomeTimeline.question(at: reveal))
                }
                .frame(width: 800, height: 460)
                .scaleEffect(scale)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.47)
                .opacity(content)

                VStack {
                    Spacer()
                    HStack {
                        Label("MADE ON YOUR MAC. KEPT ON YOUR MAC.", systemImage: "lock")
                            .font(.system(size: 9, weight: .medium))
                            .tracking(1.2)
                        Spacer()
                        Text("Click or press any key to skip")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Color(red: 0.61, green: 0.59, blue: 0.72))
                    .padding(30)
                }
                .opacity(content * WelcomeTimeline.logo(at: reveal))
            }
        }
        .ignoresSafeArea()
    }
}

/// Layered vector light trails: bounded drawing work, no textures or particle simulation.
private struct WelcomeLightField: View {
    let time: Double
    private let violet = Color(red: 0.42, green: 0.25, blue: 0.95)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color(red: 0.025, green: 0.025, blue: 0.065)
                RadialGradient(colors: [violet.opacity(0.27), violet.opacity(0.08), .clear],
                               center: UnitPoint(x: 0.5, y: 0.27),
                               startRadius: 0, endRadius: size.width * 0.65)
                RadialGradient(colors: [Color(red: 0.15, green: 0.25, blue: 0.65).opacity(0.16), .clear],
                               center: UnitPoint(x: 0.05, y: 0.85),
                               startRadius: 0, endRadius: size.width * 0.5)

                Canvas { context, bounds in
                    let sx = bounds.width / 1000
                    let sy = bounds.height / 680
                    // Each trail bends toward the flame, then opens back out at the edges.
                    for index in 0..<18 {
                        let lane = Double(index) - 8.5
                        let drift = sin(time * 0.55 + lane * 0.15) * 16
                        var path = Path()
                        path.move(to: CGPoint(x: -80 * sx, y: (380 + lane * 13 + drift) * sy))
                        path.addCurve(
                            to: CGPoint(x: 1080 * sx, y: (220 + lane * 18 - drift) * sy),
                            control1: CGPoint(x: 330 * sx, y: (20 + lane * 7 + drift) * sy),
                            control2: CGPoint(x: 620 * sx, y: (540 + lane * 6 - drift) * sy))
                        let strength = 0.12 + 0.17 * (0.5 + 0.5 * sin(lane * 0.7 + time * 0.8))
                        context.stroke(path, with: .linearGradient(
                            Gradient(stops: [
                                .init(color: violet.opacity(0), location: 0),
                                .init(color: Color(red: 0.40, green: 0.46, blue: 1).opacity(strength), location: 0.22),
                                .init(color: Color(red: 0.72, green: 0.47, blue: 1).opacity(strength), location: 0.53),
                                .init(color: Color(red: 1, green: 0.52, blue: 0.66).opacity(strength * 0.7), location: 0.78),
                                .init(color: violet.opacity(0), location: 1)
                            ]), startPoint: .zero, endPoint: CGPoint(x: bounds.width, y: 0)),
                            lineWidth: index.isMultiple(of: 5) ? 1.3 : 0.65)
                    }
                    // Sparse, deterministic points of light drift gently upward.
                    for index in 0..<32 {
                        let seed = Double(index)
                        let x = (seed * 0.61803398875).truncatingRemainder(dividingBy: 1)
                        let y = (seed * 0.381966 + 1 - time * 0.009).truncatingRemainder(dividingBy: 1)
                        let alpha = 0.10 + 0.18 * (0.5 + 0.5 * sin(seed * 2.4 + time * 0.7))
                        let diameter = index.isMultiple(of: 4) ? 2.0 : 1.0
                        let dot = CGRect(x: x * bounds.width, y: y * bounds.height, width: diameter, height: diameter)
                        context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(alpha)))
                    }
                }
                // A quiet center gives the title a clean silhouette.
                RadialGradient(colors: [.clear, .black.opacity(0.38)], center: .center,
                               startRadius: size.height * 0.15, endRadius: size.width * 0.7)
            }
            .clipped()
        }
    }
}
