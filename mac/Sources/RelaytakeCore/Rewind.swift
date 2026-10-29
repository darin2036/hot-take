import Foundation

/// Rewinding a take while it is being recorded: the last few seconds are cut off the end of the take and
/// recording carries on from there. A paused take is already a list of pieces, so a rewind drops whole pieces
/// from the end and shortens the one it lands in.
public struct RewindPlan: Equatable, Sendable {
    /// How many pieces, from the first, are kept. At least 1.
    public var keptPieces: Int
    /// The new length of the last kept piece, or nil to keep it whole.
    public var lastLength: Double?

    public init(keptPieces: Int, lastLength: Double?) {
        self.keptPieces = keptPieces
        self.lastLength = lastLength
    }

    /// The most recent footage worth keeping a take for: a rewind never goes back past this much of the start.
    public static let minimumKept = 1.0
    /// A last piece that would be left shorter than this is dropped instead of kept as a sliver.
    static let sliver = 0.25

    /// The take length to go back to, in seconds, or nil when the take is too short to rewind.
    public static func keepTime(total: Double, rewind: Double) -> Double? {
        guard rewind > 0, total - minimumKept > 0.05 else { return nil }
        return max(minimumKept, total - rewind)
    }

    /// Which pieces to keep so the take is `keep` seconds long. Nil when the take is already that short.
    public static func make(durations: [Double], keep: Double) -> RewindPlan? {
        guard !durations.isEmpty, durations.reduce(0, +) - keep > 0.05 else { return nil }
        var before = 0.0
        for (index, length) in durations.enumerated() {
            let end = before + length
            if end >= keep - 0.05 {
                if index == durations.count - 1 && end - keep <= 0.05 { return nil }
                let left = keep - before
                if left < sliver, index > 0 { return RewindPlan(keptPieces: index, lastLength: nil) }
                return RewindPlan(keptPieces: index + 1, lastLength: end - keep <= 0.05 ? nil : max(left, 0.05))
            }
            before = end
        }
        return nil
    }
}
