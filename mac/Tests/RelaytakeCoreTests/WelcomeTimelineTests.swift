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
        #expect(WelcomeTimeline.greeting(at: 1.0) == 0)
        #expect(WelcomeTimeline.logo(at: 1.4) == 1)
        #expect(WelcomeTimeline.question(at: 2.2) == 0)
        #expect(WelcomeTimeline.greeting(at: 2.2) == 1)
        #expect(WelcomeTimeline.question(at: 3.4) == 1)
    }

    @Test func theWordsAreStillThereWhileTheBackdropStartsToFade() {
        let start = WelcomeTimeline.fadeOutStart
        #expect(WelcomeTimeline.content(at: 4.0) == 1)
        #expect(WelcomeTimeline.content(at: start) < 1)
        #expect(WelcomeTimeline.content(at: WelcomeTimeline.duration) == 0)
    }

    @Test func skippingJumpsToTheFadeOutButNeverBackwards() {
        #expect(WelcomeTimeline.skipped(from: 1) == WelcomeTimeline.fadeOutStart)
        #expect(WelcomeTimeline.skipped(from: 5.3) == 5.3)
    }

    @Test func itIsFinishedOnlyAtTheEnd() {
        #expect(!WelcomeTimeline.isFinished(at: WelcomeTimeline.duration - 0.01))
        #expect(WelcomeTimeline.isFinished(at: WelcomeTimeline.duration))
    }
}
