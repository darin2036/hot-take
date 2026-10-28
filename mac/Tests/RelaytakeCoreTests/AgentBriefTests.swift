import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import RelaytakeCore

@Suite struct AgentBriefTests {
    private func line(_ start: Double, _ end: Double, _ text: String) -> CaptionSegment {
        CaptionSegment(start: start, end: end, text: text)
    }

    @Test func eachClickIsAMomentAndADoubleClickIsOne() {
        let clicks = [ClickEvent(time: 2, x: 0.1, y: 0.1), ClickEvent(time: 2.3, x: 0.1, y: 0.1), ClickEvent(time: 6, x: 0.5, y: 0.5)]
        let moments = AgentBrief.moments(clicks: clicks, transcript: [], duration: 10)
        #expect(moments.map(\.time) == [2, 6])
        #expect(moments.allSatisfy { $0.click != nil })
    }

    @Test func talkWithNoClickNearItGetsAPicture() {
        let transcript = [line(1, 3, "This button is broken."), line(10, 14, "And this list never loads.")]
        let moments = AgentBrief.moments(clicks: [ClickEvent(time: 2, x: 0.2, y: 0.2)], transcript: transcript, duration: 20)
        #expect(moments.map(\.time) == [2, 12])
        #expect(moments[0].click != nil)
        #expect(moments[1].click == nil)
    }

    @Test func aSilentRecordingWithNoClicksStillGetsOnePicture() {
        #expect(AgentBrief.moments(clicks: [], transcript: [], duration: 8) == [AgentBrief.Moment(time: 4)])
        #expect(AgentBrief.moments(clicks: [], transcript: [], duration: 0).isEmpty)
    }

    @Test func clicksPastTheEndAreDropped() {
        let moments = AgentBrief.moments(clicks: [ClickEvent(time: 30, x: 0, y: 0)], transcript: [], duration: 10)
        #expect(moments == [AgentBrief.Moment(time: 5)])
    }

    @Test func aLongWalkthroughIsThinnedKeepingClicksFirst() {
        let clicks = (0..<30).map { ClickEvent(time: Double($0) * 3, x: 0.5, y: 0.5) }
        let transcript = [line(200, 204, "One more thing.")]
        let moments = AgentBrief.moments(clicks: clicks, transcript: transcript, duration: 300, limit: 10)
        #expect(moments.count == 10)
        #expect(moments.allSatisfy { $0.click != nil })
        #expect(moments.first?.time == 0)
        #expect(moments.last?.time == 87)
        #expect(zip(moments, moments.dropFirst()).allSatisfy { $0.time < $1.time })
    }

    @Test func eachLineGoesWithTheNearestPicture() {
        let moments = [AgentBrief.Moment(time: 5), AgentBrief.Moment(time: 20)]
        let transcript = [line(0, 2, "First"), line(6, 8, "after the first click"), line(15, 18, "before the second"), line(30, 32, "end")]
        let groups = AgentBrief.narration(for: moments, transcript: transcript)
        #expect(groups.map { $0.map(\.text) } == [["First", "after the first click"], ["before the second", "end"]])
    }

    @Test func namesAndClocksSortAndRead() {
        #expect(AgentBrief.pictureName(number: 3, of: 12, time: 65.9) == "03-1m05s.png")
        #expect(AgentBrief.pictureName(number: 7, of: 120, time: 5) == "007-0m05s.png")
        #expect(AgentBrief.clock(65.9) == "1:05")
        #expect(AgentBrief.clock(3725) == "1:02:05")
    }

    @Test func theMarkdownInterleavesPicturesWithWhatWasSaid() {
        let moments = [AgentBrief.Moment(time: 2, click: ClickEvent(time: 2, x: 0.42, y: 0.18)), AgentBrief.Moment(time: 12)]
        let transcript = [line(1, 3, "Clicking save does nothing."), line(11, 13, "It should show a toast.")]
        let text = AgentBrief.markdown(
            title: "Save button bug", created: Date(timeIntervalSince1970: 0), duration: 15, captureKind: "window",
            moments: moments, pictures: ["frames/01-0m02s.png", "frames/02-0m12s.png"], transcript: transcript,
            request: AgentBrief.Request(goal: "Make Save work.", steps: ["Wire the save action", "Show a toast"]))
        #expect(text.hasPrefix("# Save button bug\n"))
        #expect(text.contains("0:15 screen recording of a window"))
        #expect(text.contains("## What they want\n\nMake Save work.\n\n1. Wire the save action\n2. Show a toast"))
        #expect(text.contains("### 1. At 0:02 — clicked 42% across, 18% down\n\n![Picture 1 at 0:02](<frames/01-0m02s.png>)\n\n> Clicking save does nothing."))
        #expect(text.contains("### 2. At 0:12\n\n![Picture 2 at 0:12](<frames/02-0m12s.png>)\n\n> It should show a toast."))
        #expect(text.contains("- [0:11] It should show a toast."))
    }

    @Test func withoutTheModelThereIsNoGoalSection() {
        let text = AgentBrief.markdown(
            title: "", created: Date(), duration: 4, captureKind: nil, moments: [AgentBrief.Moment(time: 2)],
            pictures: ["a.png"], transcript: [], request: nil)
        #expect(text.hasPrefix("# Screen recording\n"))
        #expect(!text.contains("What they want"))
        #expect(text.contains("_Nothing was said, or there is no transcript._"))
    }

    @Test func theModelsReplyIsReadInAnyCommonShape() {
        let reply = """
            Sure! Here it is.
            GOAL: "Fix the save button so it stores the draft."
            STEPS:
            1. Find the save handler
            2) Call the store
            - Show a confirmation
            • none
            """
        let request = AgentPrompt.parse(reply)
        #expect(request?.goal == "Fix the save button so it stores the draft.")
        #expect(request?.steps == ["Find the save handler", "Call the store", "Show a confirmation"])
        #expect(AgentPrompt.parse("I can't help with that.") == nil)
    }

    @Test func theRingIsDrawnWhereTheClickWas() throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        let marked = AgentBrief.marked(context.makeImage()!, click: ClickEvent(time: 0, x: 0.25, y: 0.25))
        // The ring is 12 px from the click at (50, 25) from the top-left; the far corner stays black.
        #expect(TestMedia.brightness(of: marked, region: CGRect(x: 0.18, y: 0.22, width: 0.02, height: 0.06)) > 50)
        #expect(TestMedia.brightness(of: marked, region: CGRect(x: 0.75, y: 0.7, width: 0.1, height: 0.2)) < 5)
    }

    @Test func writingMakesAPromptAndPicturesBesideTheTake() async throws {
        let video = try await TestMedia.video(seconds: 4, color: (40, 120, 200))
        let directory = video.deletingLastPathComponent().appendingPathComponent("agent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = TakeFiles(directory: directory, baseName: "Take")
        try FileManager.default.moveItem(at: video, to: files.video)
        var metadata = TakeMetadata(title: "Broken list", summary: "", created: Date(), transcript: [line(0.5, 1.5, "This list is empty.")])
        metadata.clicks = [ClickEvent(time: 3, x: 0.5, y: 0.5)]

        let first = try await AgentBrief.write(for: files, metadata: metadata, request: nil)
        #expect(first.folder == files.agentDirectory)
        #expect(first.pictures.map(\.lastPathComponent) == ["01-0m01s.png", "02-0m03s.png"])
        #expect(first.pictures.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let saved = try String(contentsOf: first.promptFile, encoding: .utf8)
        #expect(saved.contains("](<frames/01-0m01s.png>)"))
        #expect(first.copyText.contains("](<\(first.pictures[0].path)>)"))

        // Making it again replaces the earlier one and leaves no partial folder behind.
        metadata.clicks = []
        let second = try await AgentBrief.write(for: files, metadata: metadata, request: nil)
        #expect(second.pictures.count == 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: files.agentDirectory.appendingPathComponent("frames").path)
        #expect(names == ["01-0m01s.png"])
        let siblings = try FileManager.default.contentsOfDirectory(atPath: files.agentDirectory.deletingLastPathComponent().path)
        #expect(siblings == ["Take"])

        // It goes with the take: moved together, and trashed together.
        let library = directory.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let entry = try #require(TakeLibrary.load(directory: directory).first { $0.files.baseName == "Take" })
        let moved = try TakeLibrary.move(entry, toFolder: "Folder", root: directory)
        #expect(FileManager.default.fileExists(atPath: moved.agentDirectory.appendingPathComponent(AgentBrief.promptFileName).path))
        #expect(!FileManager.default.fileExists(atPath: files.agentDirectory.path))
    }
}
