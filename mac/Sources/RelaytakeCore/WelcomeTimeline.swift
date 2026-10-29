import Foundation

/// When each part of the first-launch welcome appears, in seconds from the moment it starts. The picture is a pure
/// function of this clock, so it can be checked without a window and drawn at any moment for a snapshot.
public enum WelcomeTimeline {
    /// The welcome is over: the app is fully showing.
    public static let duration = 3.0
    /// The backdrop starts to give way to the app here.
    public static let fadeOutStart = 2.5

    /// 0...1: how much of the backdrop is still covering the app.
    public static func backdrop(at time: Double) -> Double {
        1 - ramp(time, from: fadeOutStart, to: duration)
    }

    /// 0...1: the logo coming up out of the glow.
    public static func logo(at time: Double) -> Double { ease(ramp(time, from: 0.1, to: 0.6)) }

    /// 0...1: the "Welcome" line.
    public static func greeting(at time: Double) -> Double { ease(ramp(time, from: 0.45, to: 0.8)) }

    /// 0...1: the question, "What's your Hot Take?".
    public static func question(at time: Double) -> Double { ease(ramp(time, from: 0.75, to: 1.25)) }

    /// 0...1: how much of the logo and words remain. They leave a little ahead of the backdrop.
    public static func content(at time: Double) -> Double {
        1 - ease(ramp(time, from: fadeOutStart - 0.15, to: fadeOutStart + 0.25))
    }

    /// The start time to use after a click or key press: straight to the fade-out, or later if it is already past it.
    public static func skipped(from time: Double) -> Double { max(time, fadeOutStart) }

    public static func isFinished(at time: Double) -> Bool { time >= duration }

    private static func ramp(_ time: Double, from: Double, to: Double) -> Double {
        min(1, max(0, (time - from) / (to - from)))
    }

    /// Smoothstep, so things start and stop gently.
    private static func ease(_ value: Double) -> Double { value * value * (3 - 2 * value) }
}
