import AVFoundation
import CoreGraphics
import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct TextOpacityTests {
    @Test func fadesInAndOutAtTheRightMoments() {
        let overlay = TextOverlay(text: "x", start: 2, end: 4)
        #expect(overlay.opacity(at: 1) == 0)
        #expect(overlay.opacity(at: 3) == 1)
        #expect(overlay.opacity(at: 5) == 0)
        #expect(abs(overlay.opacity(at: 2.075) - 0.5) < 0.001)   // halfway through the fade in
        #expect(abs(overlay.opacity(at: 3.925) - 0.5) < 0.001)   // halfway through the fade out
    }

    @Test func veryShortTextStillReachesFullOpacity() {
        let overlay = TextOverlay(text: "x", start: 1, end: 1.3)
        #expect(overlay.opacity(at: 1.15) > 0.99)
        #expect(overlay.opacity(at: 0) == 0 && overlay.opacity(at: 2) == 0)
    }
}

@Suite struct BrightnessHelperTests {
    @Test func readsTheTopOfAPictureAsTheTop() {
        let context = CGContext(
            data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 20, width: 40, height: 20))  // y grows upward: this is the top half
        let image = context.makeImage()!
        #expect(TestMedia.brightness(of: image, region: CGRect(x: 0, y: 0, width: 1, height: 0.4)) > 200)
        #expect(TestMedia.brightness(of: image, region: CGRect(x: 0, y: 0.6, width: 1, height: 0.4)) < 50)
    }
}

@Suite(.serialized) struct StudioRenderTests {
    @Test func cutsTextAndMusicRenderIntoOneFile() async throws {
        let source = try await TestMedia.video(seconds: 6, color: (20, 30, 120), toneHz: 440)
        let song = try TestMedia.tone(seconds: 10, frequency: 220, amplitude: 0.5)

        var project = StudioProject(duration: 6)
        try project.remove(TimeSpan(start: 2, end: 3))  // 5 s left
        let text = project.addText(at: 1, text: "HELLO")
        project.updateText(text) { $0.start = 1; $0.end = 3; $0.y = 0.2; $0.heightFraction = TextOverlay.Size.large.heightFraction; $0.showsBackground = false }  // white letters on a dark picture must brighten it
        let music = project.addMusic(url: song, name: "Song", fileDuration: 10)
        project.updateClip(music) { $0.volume = 0.5; $0.fadeIn = 0; $0.fadeOut = 0 }
        project.originalVolume = 0  // a full redub keeps only the added audio

        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: project, to: out) { _ in }

        let length = try await TestMedia.duration(of: out)
        #expect(abs(length - 5) < 0.2, "cut a second out of 6 s: \(length)")

        // Text is drawn at the top, only while it should show.
        let topWhileShowing = try await TestMedia.brightness(of: out, at: 2, region: CGRect(x: 0.2, y: 0.05, width: 0.6, height: 0.3))
        let topAfter = try await TestMedia.brightness(of: out, at: 4, region: CGRect(x: 0.2, y: 0.05, width: 0.6, height: 0.3))
        let bottomWhileShowing = try await TestMedia.brightness(of: out, at: 2, region: CGRect(x: 0.2, y: 0.7, width: 0.6, height: 0.25))
        let bottomAfter = try await TestMedia.brightness(of: out, at: 4, region: CGRect(x: 0.2, y: 0.7, width: 0.6, height: 0.25))
        #expect(topWhileShowing > topAfter + 4, "text should brighten the top: \(topWhileShowing) vs \(topAfter)")
        #expect(abs(bottomWhileShowing - bottomAfter) < 2, "the bottom should not change: \(bottomWhileShowing) vs \(bottomAfter)")

        // Original sound muted: what is left is the 220 Hz song at about half volume (0.5 × 0.5 peak → rms ≈ 0.18).
        let level = try await TestMedia.rms(of: out, from: 0.5, to: 4.5)
        #expect(level > 0.12 && level < 0.25, "music only: \(level)")
    }

    @Test func originalSoundAndMusicMixAtTheirOwnVolumes() async throws {
        let source = try await TestMedia.video(seconds: 4, color: (60, 60, 60), toneHz: 440)  // rms ≈ 0.35
        let song = try TestMedia.tone(seconds: 4, frequency: 220, amplitude: 0.5)

        var original = StudioProject(duration: 4)
        let loud = try await render(source, original)
        #expect(loud > 0.28 && loud < 0.42, "original alone: \(loud)")

        original.originalVolume = 0.5
        #expect(try await render(source, original) < loud * 0.7)  // turned down

        var mixed = StudioProject(duration: 4)
        let id = mixed.addMusic(url: song, name: "Song", fileDuration: 4)
        mixed.updateClip(id) { $0.volume = 1; $0.fadeIn = 0; $0.fadeOut = 0 }
        #expect(try await render(source, mixed) > loud * 1.15)  // adding music makes it louder
    }

    @Test func shortMusicLoopsAndAVoiceoverStartsWhereItWasPlaced() async throws {
        let source = try await TestMedia.video(seconds: 6, color: (60, 60, 60))  // no sound of its own
        let jingle = try TestMedia.tone(seconds: 2, frequency: 330, amplitude: 0.6)
        let voice = try TestMedia.tone(seconds: 2, frequency: 500, amplitude: 0.6)

        var project = StudioProject(duration: 6)
        let bed = project.addMusic(url: jingle, name: "Jingle", fileDuration: 2)
        project.updateClip(bed) { $0.fadeIn = 0; $0.fadeOut = 0; $0.volume = 1 }
        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: project, to: out) { _ in }
        let late = try await TestMedia.rms(of: out, from: 4.2, to: 5.8)
        #expect(late > 0.2, "the 2 s jingle should loop to fill 6 s: \(late)")

        // A voiceover placed at 3 s is silent before it and audible after.
        var dub = StudioProject(duration: 6)
        dub.addVoiceover(url: voice, name: "Voiceover", fileDuration: 2, start: 3)
        let dubOut = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: dub, to: dubOut) { _ in }
        #expect(try await TestMedia.rms(of: dubOut, from: 0.2, to: 2.6) < 0.03)
        #expect(try await TestMedia.rms(of: dubOut, from: 3.3, to: 4.7) > 0.2)
        #expect(try await TestMedia.rms(of: dubOut, from: 5.3, to: 5.9) < 0.03)
    }

    @Test func thePreviewIsExactlyAsLongAsTheEditedVideo() async throws {
        let source = try await TestMedia.video(seconds: 8, color: (30, 30, 30), toneHz: 440)
        let song = try TestMedia.tone(seconds: 60, frequency: 220)
        let voice = try TestMedia.tone(seconds: 20, frequency: 500)  // longer than the video
        var project = StudioProject(duration: 8)
        try project.remove(TimeSpan(start: 2, end: 4))  // 6 s left
        project.addMusic(url: song, name: "Song", fileDuration: 60)
        project.addVoiceover(url: voice, name: "Voiceover", fileDuration: 20, start: 1)
        #expect(project.outputDuration == 6)

        let preview = try await StudioComposer.build(asset: AVURLAsset(url: source), project: project, burnText: false)
        #expect(abs(preview.composition.duration.seconds - 6) < 0.05, "music and voiceover must not stretch the video")
        #expect(preview.videoComposition == nil)  // text is drawn on top in the preview, not baked in
        let muted = try await StudioComposer.build(asset: AVURLAsset(url: source), project: project, burnText: false, muteOriginal: true)
        #expect(muted.audioMix != nil)
    }

    @Test func textColorAndBoxColorReachTheSavedPicture() async throws {
        let source = try await TestMedia.video(seconds: 4, color: (60, 60, 60))
        var project = StudioProject(duration: 4)
        let red = project.addText(at: 0.5, text: "RED TEXT")
        project.updateText(red) {
            $0.start = 0.5; $0.end = 3.5; $0.y = 0.2; $0.heightFraction = TextOverlay.Size.huge.heightFraction
            $0.fontFamily = TextOverlay.fontFamilies.contains("Georgia") ? "Georgia" : TextOverlay.systemFont
            $0.isItalic = true; $0.showsBackground = false; $0.color = TextColor(red: 1, green: 0.1, blue: 0.1)
        }
        let boxed = project.addText(at: 0.5, text: "BOX")
        project.updateText(boxed) {
            $0.start = 0.5; $0.end = 3.5; $0.y = 0.8; $0.heightFraction = TextOverlay.Size.huge.heightFraction
            $0.color = .black; $0.showsBackground = true; $0.boxColor = .white
        }
        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: project, to: out) { _ in }

        let top = CGRect(x: 0.2, y: 0.02, width: 0.6, height: 0.36)
        let showing = try await TestMedia.channels(of: out, at: 2, region: top)
        let gone = try await TestMedia.channels(of: out, at: 3.8, region: top)
        #expect(showing.red - showing.blue > gone.red - gone.blue + 3, "red text should push the red channel up: \(showing) vs \(gone)")

        let bottom = CGRect(x: 0.2, y: 0.62, width: 0.6, height: 0.36)
        let box = try await TestMedia.brightness(of: out, at: 2, region: bottom)
        let after = try await TestMedia.brightness(of: out, at: 3.8, region: bottom)
        #expect(box > after + 12, "a white box behind black text should brighten the area: \(box) vs \(after)")
    }

    @Test func aSilentCopyHasNoAudioAndAMovCopyIsAQuickTimeFile() async throws {
        let source = try await TestMedia.video(seconds: 3, color: (10, 10, 10), toneHz: 440)
        let song = try TestMedia.tone(seconds: 3, frequency: 220)
        var project = StudioProject(duration: 3)
        project.addMusic(url: song, name: "Song", fileDuration: 3)

        let silent = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: project, to: silent, includeAudio: false) { _ in }
        #expect(try await AVURLAsset(url: silent).loadTracks(withMediaType: .audio).isEmpty, "no original sound and no music")
        #expect(try await AVURLAsset(url: silent).loadTracks(withMediaType: .video).count == 1)

        let mov = TestMedia.tempURL("mov")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: project, to: mov) { _ in }
        let header = try Data(contentsOf: mov).prefix(12)
        #expect(String(decoding: header.dropFirst(4), as: UTF8.self) == "ftypqt  ", "a .mov name should give a MOV file type")
        #expect(try await TestMedia.rms(of: mov, from: 0.3, to: 2.7) > 0.1)  // and it still has its sound
    }

    @Test func aProjectWithNoTextStillExports() async throws {
        let source = try await TestMedia.video(seconds: 3, color: (10, 10, 10), toneHz: 440)
        var project = StudioProject(duration: 3)
        try project.keepOnly(TimeSpan(start: 1, end: 2.5))
        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: project, to: out) { _ in }
        #expect(abs(try await TestMedia.duration(of: out) - 1.5) < 0.2)
    }

    private func render(_ source: URL, _ project: StudioProject) async throws -> Double {
        let out = TestMedia.tempURL("mp4")
        try await StudioComposer.export(asset: AVURLAsset(url: source), project: project, to: out) { _ in }
        return try await TestMedia.rms(of: out, from: 0.3, to: 3.6)
    }
}
