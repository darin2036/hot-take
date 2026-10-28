import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import RelaytakeCore

@Suite struct HotkeyTests {
    @Test func aBindingRoundTripsThroughItsStoredText() {
        let binding = HotkeyBinding(keyCode: 15, modifiers: [.control, .option, .command])
        #expect(HotkeyBinding(stored: binding.stored) == binding)
        #expect(binding.display == "⌃⌥⌘R")
        #expect(HotkeyBinding(keyCode: 36, modifiers: [.shift, .command]).display == "⇧⌘↩")
    }

    @Test func damagedStoredTextIsRefusedNotGuessed() {
        for text in ["", "15", "15:99", "x:1", "15:-1", "999:1", "15:1:2"] { #expect(HotkeyBinding(stored: text) == nil, "\(text)") }
    }

    @Test func aShortcutNeedsACommandOptionOrControlKey() {
        #expect(HotkeyBinding(keyCode: 15, modifiers: []).problem == .needsModifier)
        #expect(HotkeyBinding(keyCode: 15, modifiers: .shift).problem == .needsModifier)
        #expect(HotkeyBinding(keyCode: 15, modifiers: .option).problem == nil)
        #expect(HotkeyBinding(keyCode: 15, modifiers: [.shift, .control]).problem == nil)
    }

    @Test func combinationsThatBelongToTheSystemAreRefused() {
        let spotlight = HotkeyBinding(keyCode: 49, modifiers: .command)
        if case .reserved = spotlight.problem {} else { Issue.record("⌘Space should be refused") }
        if case .reserved = HotkeyBinding(keyCode: 21, modifiers: [.command, .shift]).problem {} else { Issue.record("⇧⌘4 should be refused") }
        #expect(HotkeyBinding(keyCode: 21, modifiers: [.command, .shift, .option]).problem == nil)
    }

    @Test func theStandardShortcutsAreValidAndDistinct() {
        let all = HotkeyAction.allCases.map(\.standard)
        #expect(all.allSatisfy { $0.problem == nil })
        #expect(Set(all).count == all.count)
    }

    @Test func missingActionsUseTheirStandardKeysAndEmptyMeansOff() {
        let result = HotkeyResolver.resolve(stored: [.pause: ""])
        #expect(result.bindings[.startStop] == HotkeyAction.startStop.standard)
        #expect(result.bindings[.pause] == nil && result.refused[.pause] == nil, "turned off, not refused")
        #expect(result.bindings[.screenshot] == HotkeyAction.screenshot.standard)
    }

    @Test func twoActionsOnTheSameKeysKeepTheFirstAndExplainTheSecond() {
        let same = HotkeyAction.startStop.standard.stored
        let result = HotkeyResolver.resolve(stored: [.pause: same])
        #expect(result.bindings[.startStop] != nil && result.bindings[.pause] == nil)
        #expect(result.refused[.pause]?.contains("Start or stop recording") == true)
    }

    @Test func aBadSavedValueIsReportedAndOthersStillWork() {
        let result = HotkeyResolver.resolve(stored: [.startStop: "garbage", .screenshot: HotkeyBinding(keyCode: 15, modifiers: []).stored])
        #expect(result.refused[.startStop] != nil && result.refused[.screenshot] != nil)
        #expect(result.bindings[.pause] != nil)
    }
}

@Suite struct QuickCaptureTests {
    @Test func theLastScreenIsUsedWhileItIsStillConnected() {
        #expect(QuickCapturePlan.display(last: 7, connected: [3, 7], main: 3) == 7)
        #expect(QuickCapturePlan.display(last: 9, connected: [3, 7], main: 3) == 3, "unplugged: back to the main screen")
        #expect(QuickCapturePlan.display(last: nil, connected: [5, 7], main: 99) == 5)
        #expect(QuickCapturePlan.display(last: nil, connected: [], main: nil) == nil)
    }
}

@Suite struct CaptureExclusionTests {
    @Test func notificationCenterIsLeftOutOnlyWhenAsked() {
        let on = CaptureExclusions.bundleIdentifiers(ownApp: "org.relaytake.mac", includeOwnApp: false, hideNotifications: true)
        #expect(on == ["org.relaytake.mac", CaptureExclusions.notificationCenter])
        let off = CaptureExclusions.bundleIdentifiers(ownApp: "org.relaytake.mac", includeOwnApp: false, hideNotifications: false)
        #expect(off == ["org.relaytake.mac"])
    }

    @Test func recordingTheAppItselfKeepsItsWindowsButStillHidesNotifications() {
        let ids = CaptureExclusions.bundleIdentifiers(ownApp: "org.relaytake.mac", includeOwnApp: true, hideNotifications: true)
        #expect(ids == [CaptureExclusions.notificationCenter])
    }
}

@Suite struct ScreenshotTests {
    private var date: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9, minute: 30, second: 15))!
    }

    @Test func screenshotsAreNamedLikeTakes() {
        #expect(Screenshot.fileName(for: date) == "Hot Take Screenshot 2026-10-21 at 09.30.15.png")
    }

    @Test func twoShotsInOneSecondNeverOverwriteEachOther() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = Screenshot.uniqueURL(in: folder, for: date)
        try Data([1]).write(to: first)
        let second = Screenshot.uniqueURL(in: folder, for: date)
        #expect(second != first && second.lastPathComponent.hasSuffix(" 2.png"))
        try Data([1]).write(to: second)
        #expect(Screenshot.uniqueURL(in: folder, for: date).lastPathComponent.hasSuffix(" 3.png"))
    }

    @Test func aPNGIsWrittenAndReadsBackAtTheSameSize() throws {
        let context = CGContext(
            data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("shot.png")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Screenshot.writePNG(context.makeImage()!, to: url)
        let data = try Data(contentsOf: url)
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47], "a PNG signature")
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        #expect(image.width == 64 && image.height == 32)
    }
}

@Suite struct PlaybackAndReadingTests {
    @Test func speedsAreLabelledAndUnknownOnesFallBackToNormal() {
        #expect(PlaybackSpeed.choices.map(PlaybackSpeed.label) == ["0.5×", "0.75×", "1×", "1.25×", "1.5×", "2×"])
        #expect(PlaybackSpeed.valid(1.5) == 1.5)
        #expect(PlaybackSpeed.valid(3) == 1 && PlaybackSpeed.valid(0) == 1)
    }

    @Test func readingTimeFollowsTheWordCount() {
        let hundredFifty = Array(repeating: "word", count: 150).joined(separator: " ")
        #expect(ReadingTime.seconds(of: hundredFifty) == 60)
        #expect(ReadingTime.label(for: hundredFifty) == "About 1 min")
        #expect(ReadingTime.label(for: Array(repeating: "word", count: 200).joined(separator: " ")) == "About 1 min 20 s")
        #expect(ReadingTime.label(for: "  \n ") == "")
        #expect(ReadingTime.label(for: Array(repeating: "word", count: 75).joined(separator: "\n")) == "About 30 s")
    }
}

@Suite struct ThumbnailMetadataTests {
    @Test func theChosenThumbnailMomentSurvivesTheNotesFileAndARemake() throws {
        var metadata = TakeMetadata(title: "T", summary: "", created: Date())
        metadata.thumbnailTime = 12.5
        let decoded = try TakeMetadata.decode(metadata.encoded())
        #expect(decoded.thumbnailTime == 12.5)
        var rewritten = TakeMetadata(title: "New", summary: "S", created: Date())
        rewritten.keepCapture(of: decoded)
        #expect(rewritten.thumbnailTime == 12.5)
    }

    @Test func olderNotesFilesHaveNoThumbnailChoice() throws {
        let json = #"{"title":"T","summary":"","created":"2026-10-21T09:30:15Z"}"#
        #expect(try TakeMetadata.decode(Data(json.utf8)).thumbnailTime == nil)
    }
}
