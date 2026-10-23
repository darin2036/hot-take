import Testing
@testable import RelaytakeCore

@Suite struct QualityTests {
    @Test func scalesRetinaAndPortraitWithoutUpscaling() {
        let small = VideoQuality.small.dimensions(width: 3840, height: 2160)
        #expect(small.width == 1280 && small.height == 720)
        let portrait = VideoQuality.medium.dimensions(width: 2160, height: 3840)
        #expect(portrait.width == 1080 && portrait.height == 1920)
        let tiny = VideoQuality.large.dimensions(width: 641, height: 481)
        #expect(tiny.width == 640 && tiny.height == 480)
        let ultrawide = VideoQuality.small.dimensions(width: 3440, height: 1440)
        #expect(ultrawide.width == 1280 && ultrawide.height % 2 == 0 && ultrawide.height < 720)
    }
    @Test func estimatesAccountForAudioAndDuration() {
        #expect(VideoQuality.small.estimatedMB(seconds: 60) == 5.73)
        #expect(VideoQuality.small.estimatedMB(seconds: 60, audio: false) == 5.25)
        #expect(VideoQuality.medium.estimatedMB(seconds: 120) > VideoQuality.medium.estimatedMB(seconds: 60))
        #expect(VideoQuality.large.estimatedMB(seconds: 60) > VideoQuality.medium.estimatedMB(seconds: 60))
    }
}

@Suite struct CustomQualityTests {
    @Test func customFollowsLarge() {
        #expect(VideoQuality.allCases.map(\.rawValue) == ["small", "medium", "large", "custom"])
    }
    @Test func customControlsDriveSizeAndScaling() {
        let value = EncodingSettings(resolution: 480, fps: 12, videoKbps: 450, audioKbps: 48, channels: 1)
        #expect(value.fps == 12 && value.videoBitrate == 450000 && value.audioBitrate == 48000 && value.channels == 1)
        #expect(abs(value.estimatedMB(seconds: 60) - 3.735) < 0.001)
        let size = value.dimensions(width: 1920, height: 1080)
        #expect(size.width == 852 && size.height == 478)
    }
    @Test func invalidValuesStayInsideEncoderLimits() {
        let value = EncodingSettings(resolution: 9999, fps: -1, videoKbps: 0, audioKbps: 9000, channels: 8)
        #expect(value.shortEdge == 2160 && value.fps == 5)
        #expect(value.videoBitrate == 200000 && value.audioBitrate == 256000 && value.channels == 2)
    }
}

@Suite struct SuggestedBitrateTests {
    @Test func theRuleReproducesTheMediumPreset() {
        #expect(EncodingSettings.suggestedVideoKbps(resolution: 1080, fps: 24) == 1600)
    }

    @Test func moreResolutionOrFramesMeanAHigherBitrateAndSoABiggerEstimate() {
        let base = EncodingSettings.suggestedVideoKbps(resolution: 1080, fps: 24)
        #expect(EncodingSettings.suggestedVideoKbps(resolution: 1440, fps: 24) > base)
        #expect(EncodingSettings.suggestedVideoKbps(resolution: 720, fps: 24) < base)
        #expect(EncodingSettings.suggestedVideoKbps(resolution: 1080, fps: 60) > base)
        #expect(EncodingSettings.suggestedVideoKbps(resolution: 1080, fps: 10) < base)
        let small = EncodingSettings(resolution: 720, fps: 15, videoKbps: EncodingSettings.suggestedVideoKbps(resolution: 720, fps: 15))
        let large = EncodingSettings(resolution: 2160, fps: 60, videoKbps: EncodingSettings.suggestedVideoKbps(resolution: 2160, fps: 60))
        #expect(large.estimatedMB(seconds: 60) > small.estimatedMB(seconds: 60) * 5)
    }

    @Test func theSuggestionStaysInsideTheSupportedRange() {
        #expect(EncodingSettings.suggestedVideoKbps(resolution: 1, fps: 1) >= 200)
        #expect(EncodingSettings.suggestedVideoKbps(resolution: 99999, fps: 999) <= 20000)
    }
}
