import Testing
@testable import RelaytakeCore

@Suite struct RewindTests {
    @Test func goesBackWithinTheLastPiece() {
        #expect(RewindPlan.keepTime(total: 30, rewind: 10) == 20)
        #expect(RewindPlan.make(durations: [30], keep: 20) == RewindPlan(keptPieces: 1, lastLength: 20))
        #expect(RewindPlan.make(durations: [10, 30], keep: 30) == RewindPlan(keptPieces: 2, lastLength: 20))
    }

    @Test func dropsWholePiecesAndShortensTheOneItLandsIn() {
        #expect(RewindPlan.make(durations: [20, 5, 4], keep: 15) == RewindPlan(keptPieces: 1, lastLength: 15))
        #expect(RewindPlan.make(durations: [20, 5, 4], keep: 22) == RewindPlan(keptPieces: 2, lastLength: 2))
    }

    @Test func aBoundaryKeepsWholePieces() {
        #expect(RewindPlan.make(durations: [20, 5, 4], keep: 25) == RewindPlan(keptPieces: 2, lastLength: nil))
        #expect(RewindPlan.make(durations: [20, 5, 4], keep: 20) == RewindPlan(keptPieces: 1, lastLength: nil))
    }

    @Test func doesNotLeaveASliver() {
        #expect(RewindPlan.make(durations: [20, 5, 4], keep: 20.1) == RewindPlan(keptPieces: 1, lastLength: nil))
        // The first piece is always kept, even if it is short.
        #expect(RewindPlan.make(durations: [20], keep: 1) == RewindPlan(keptPieces: 1, lastLength: 1))
    }

    @Test func tooShortToRewind() {
        #expect(RewindPlan.keepTime(total: 1, rewind: 10) == nil)
        #expect(RewindPlan.keepTime(total: 0.5, rewind: 10) == nil)
        #expect(RewindPlan.keepTime(total: 8, rewind: 10) == 1)  // goes back as far as the start, leaving a second
        #expect(RewindPlan.keepTime(total: 30, rewind: 0) == nil)
        #expect(RewindPlan.make(durations: [20], keep: 20) == nil)
        #expect(RewindPlan.make(durations: [], keep: 5) == nil)
    }
}
