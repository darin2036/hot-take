import Testing

@testable import RelaytakeCore

@Suite struct WelcomeTimelineTests {
    @Test func theBackdropCoversTheAppUntilItFadesOut() {
        #expect(WelcomeTimeline.backdrop(at: 0) == 1)
        #expect(WelcomeTimeline.backdrop(at: WelcomeTimeline.fadeOutStart) == 1)
        #expect(WelcomeTimeline.backdrop(at: WelcomeTimeline.duration) == 0)
        #expect(WelcomeTimeline.backdrop(at: WelcomeTimeline.duration + 5) == 0)
    }

    @Test func theLogoThenTheGreetingThenTheQuestionAppearInOrder() {
        #expect(WelcomeTimeline.logo(at: 0) == 0)
        #expect(WelcomeTimeline.greeting(at: 0.4) == 0)
        #expect(WelcomeTimeline.logo(at: 0.6) == 1)
        #expect(WelcomeTimeline.question(at: 0.7) == 0)
        #expect(WelcomeTimeline.greeting(at: 0.8) == 1)
        #expect(WelcomeTimeline.question(at: 1.25) == 1)
    }

    @Test func theWordsAreStillThereWhileTheBackdropStartsToFade() {
        let start = WelcomeTimeline.fadeOutStart
        #expect(WelcomeTimeline.content(at: 2.0) == 1)
        #expect(WelcomeTimeline.content(at: start) < 1)
        #expect(WelcomeTimeline.content(at: WelcomeTimeline.duration) == 0)
    }

    @Test func skippingJumpsToTheFadeOutButNeverBackwards() {
        #expect(WelcomeTimeline.skipped(from: 1) == WelcomeTimeline.fadeOutStart)
        #expect(WelcomeTimeline.duration - WelcomeTimeline.skipped(from: 1) <= 0.5)
        #expect(WelcomeTimeline.skipped(from: 2.7) == 2.7)
    }

    @Test func itIsFinishedOnlyAtTheEnd() {
        #expect(WelcomeTimeline.duration <= 3)
        #expect(!WelcomeTimeline.isFinished(at: WelcomeTimeline.duration - 0.01))
        #expect(WelcomeTimeline.isFinished(at: WelcomeTimeline.duration))
    }
}
