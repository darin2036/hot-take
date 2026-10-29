import AVFoundation
import AppKit
import RelaytakeCore
import SwiftUI

/// `Hot Take --studio-snapshot Take.mp4 song.m4a out.png` draws the Studio, with a few sample edits
/// (a cut, text, music), into a PNG so its layout can be checked without a screen. The player
/// itself does not render offscreen, so the preview area shows black.
@MainActor
enum StudioSnapshot {
    static func run(video: URL, music: URL?, output: URL, width: CGFloat, height: CGFloat, variant: String = "studio") async -> Bool {
        let directory = video.deletingLastPathComponent()
        guard let take = TakeLibrary.load(directory: directory).first(where: { $0.files.baseName == video.deletingPathExtension().lastPathComponent }) else { return false }
        let model = StudioModel(take: take, library: LibraryModel.shared)
        await model.load()
        model.edit { project in
            try? project.remove(TimeSpan(start: 6, end: 8))
            let title = project.addText(at: 1, text: "Quarterly demo")
            project.updateText(title) { $0.start = 1; $0.end = 5; $0.y = 0.15 }
            let second = project.addText(at: 3, text: "Watch the total")
            project.updateText(second) { $0.start = 3; $0.end = 8; $0.y = 0.85 }
            project.originalVolume = 1
        }
        if let music {
            model.addMusic(from: music)
            try? await Task.sleep(for: .seconds(1))
        }
        if variant == "voiceover", let music {
            model.edit { project in project.addVoiceover(url: music, name: "Voiceover", fileDuration: 8, start: 2) }
            if let clip = model.project.clips.first(where: { $0.kind == .voiceover }) { model.loadLevels(for: music); model.selection = .clip(clip.id) }
        }
        model.loadLevels(for: video)
        try? await Task.sleep(for: .seconds(2))
        if variant != "voiceover", variant != "splice", variant != "gap" { model.selection = model.project.texts.first.map { .text($0.id) } ?? .none }
        // "splice": two splices, the middle part chosen. "gap": that part removed, so an edge can be dragged back out.
        if variant == "splice" || variant == "gap" {
            model.selection = .none
            model.seek(to: 12); model.splice()
            model.seek(to: 24); model.splice()
            if variant == "splice" { model.selectPart(atOutput: 18) }
            if variant == "gap", let part = model.project.cuts.partSpans.dropFirst().first { model.removeSection(part) }
        }

        // "marks": an arrow, a box and a blur on the picture, rings at the noted clicks, and the arrow chosen.
        if variant == "marks" {
            model.edit { project in
                project.setClickHighlights(on: true, clicks: model.clicks)
                let box = project.addShape(.box, at: 2)
                project.updateShape(box) { $0.start = 2; $0.end = 7 }
                let blur = project.addShape(.blur, at: 4)
                project.updateShape(blur) { $0.start = 4; $0.end = 9 }
            }
            model.edit { project in
                let id = project.addShape(.arrow, at: 1)
                project.updateShape(id) { $0.start = 1; $0.end = 6 }
            }
            if let arrow = model.project.shapes.last { model.select(.shape(arrow.id)) }
            model.seek(to: 3)
        }

        if variant == "tighten" {
            model.showTighten([
                EditSuggestion(kind: .silence, span: TimeSpan(start: 2.2, end: 4.4), reason: "Quiet for 2.2 s"),
                EditSuggestion(kind: .restart, span: TimeSpan(start: 9, end: 11.4), reason: "Said again just after: \"So today I want to show you\""),
                EditSuggestion(kind: .silence, span: TimeSpan(start: 15, end: 17.6), reason: "Quiet for 2.6 s"),
                EditSuggestion(kind: .filler, span: TimeSpan(start: 1.2, end: 1.7), reason: "Filler: \u{201C}um\u{201D}"),
            ])
        }

        // "transcript": the second line cut from the Transcript panel, and the fourth selected.
        if variant == "transcript" {
            model.selection = .none
            model.cutLines([1])
            model.clickLine(3, shift: false, command: false)
        }

        let root: AnyView
        switch variant {
        case "theater":
            let request = TheaterRequest(title: "Studio preview") { AnyView(StudioStage(model: model)) }
            root = AnyView(TheaterView(request: request, library: LibraryModel.shared))
        case "style":
            if let id = model.project.texts.first?.id { model.edit { $0.updateText(id) { $0.fontFamily = "Georgia"; $0.isItalic = true; $0.color = TextColor(red: 1, green: 0.84, blue: 0.1) } } }
            root = AnyView(model.project.texts.first.map { TextStylePanel(model: model, id: $0.id) } ?? nil)
        case "buttons":
            root = AnyView(
                ZStack(alignment: .topTrailing) {
                    Color.black
                    PlaybackButtons(title: "Demo", owner: model, library: LibraryModel.shared, content: { AnyView(Color.black) }).padding(10)
                })
        default:
            root = AnyView(StudioView(model: model, close: {}))
        }
        let host = NSHostingView(rootView: root.frame(width: width, height: height).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .seconds(1.5))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: output)) != nil
    }
}

/// `Hot Take --playback-check` exercises the pop-out and full-screen window controller and prints results.
@MainActor
enum PlaybackCheck {
    static func run() async -> Bool {
        var ok = true
        func check(_ label: String, _ condition: Bool) {
            print((condition ? "ok   " : "FAIL ") + label)
            if !condition { ok = false }
        }
        // Studio shortcuts (space, delete, escape) must stand down while a text field has the keyboard.
        let field = NSTextField(string: "type here")
        let typingWindow = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 240, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
        typingWindow.contentView?.addSubview(field)
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 24)
        typingWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .milliseconds(300))
        typingWindow.makeFirstResponder(nil)
        check("not typing when no text field is active", !StudioView.isTyping(in: typingWindow))
        typingWindow.makeFirstResponder(field)
        try? await Task.sleep(for: .milliseconds(150))
        check("typing is detected while a text field is being edited", StudioView.isTyping(in: typingWindow))
        typingWindow.makeFirstResponder(nil)
        try? await Task.sleep(for: .milliseconds(150))
        check("shortcuts work again after leaving the text field", !StudioView.isTyping(in: typingWindow))
        typingWindow.close()

        let owner = NSObject()
        let windows = PlayerWindows.shared

        let microphones = Microphone.available()
        print("microphones:", microphones.map(\.name).joined(separator: " | "))
        check("the microphone list starts with the default and has a real input", microphones.first?.id == "" && microphones.count >= 1)
        check("the saved default resolves to a device", Microphone.chosen(id: "").device != nil)
        check("an unplugged microphone falls back to the default", Microphone.chosen(id: "no-such-device").fellBack)

        let pop = windows.popOut(owner: owner, title: "Check pop-out", aspect: CGSize(width: 16, height: 9), content: AnyView(Color.black))
        try? await Task.sleep(for: .milliseconds(300))
        check("pop-out window is on screen", pop.isVisible)
        check("pop-out floats above other windows", pop.level == .floating)
        check("pop-out keeps the video's shape", abs(pop.contentAspectRatio.width / pop.contentAspectRatio.height - 16.0 / 9.0) < 0.01)
        check("one window is tracked", windows.openCount == 1)

        // Full screen is created without actually entering it, so this does not take over the display.
        let full = windows.fullScreen(owner: owner, title: "Check full screen", content: AnyView(Color.black), enterNow: false)
        check("full-screen window can go full screen", full.collectionBehavior.contains(.fullScreenPrimary))
        check("two windows are tracked", windows.openCount == 2)
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: full)
        windows.windowDidExitFullScreen(Notification(name: NSWindow.didExitFullScreenNotification, object: full))
        try? await Task.sleep(for: .milliseconds(200))
        check("leaving full screen closes that window", !full.isVisible && windows.openCount == 1)

        windows.closeAll(ownedBy: owner)
        try? await Task.sleep(for: .milliseconds(200))
        check("closing by owner removes the pop-out", !pop.isVisible && windows.openCount == 0)

        let other = NSObject()
        let kept = windows.popOut(owner: other, title: "Other owner", aspect: nil, content: AnyView(Color.black))
        windows.closeAll(ownedBy: owner)
        check("closing one owner leaves another owner's window", kept.isVisible && windows.openCount == 1)
        windows.closeAll(ownedBy: other)
        return ok
    }
}

/// `Hot Take --studio-render in.mp4 out.ext SIZE FORMAT [--no-audio]` saves a sample edit (a cut and some
/// text) the way Save Copy and Export do. SIZE is original, small, medium, large; FORMAT is mp4, mov, webm.
/// `Hot Take --studio-save Take.mp4 SIZE [--unedited]` runs the library Save Copy path itself.
@MainActor
enum StudioChecks {
    private static func options(size: String, noAudio: Bool) -> StudioSaveOptions {
        let quality = VideoQuality(rawValue: size).map { EncodingPreferences.resolve($0) }
        return StudioSaveOptions(quality: quality, includeAudio: !noAudio)
    }

    private static func sampleProject(duration: Double, edited: Bool) -> StudioProject {
        var project = StudioProject(duration: duration)
        guard edited else { return project }
        try? project.remove(TimeSpan(start: 2, end: 3))
        let id = project.addText(at: 0.5, text: "HELLO")
        project.updateText(id) { $0.start = 0.5; $0.end = 4; $0.y = 0.2; $0.heightFraction = TextOverlay.Size.large.heightFraction; $0.showsBackground = false }
        return project
    }

    static func render(video: URL, output: URL, size: String, format: String, noAudio: Bool) async -> Bool {
        guard let format = VideoExportFormat(rawValue: format) else { print("unknown format"); return false }
        let asset = AVURLAsset(url: video)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        do {
            try await StudioSaver.render(
                asset: asset, project: sampleProject(duration: duration, edited: true), to: output, format: format,
                options: options(size: size, noAudio: noAudio)
            ) { _ in }
            print("rendered", output.path)
            return true
        } catch {
            print("error:", error.localizedDescription)
            return false
        }
    }

    static func save(video: URL, size: String, edited: Bool) async -> Bool {
        let directory = video.deletingLastPathComponent()
        guard let take = TakeLibrary.load(directory: directory).first(where: { $0.files.baseName == video.deletingPathExtension().lastPathComponent })
        else { print("not found"); return false }
        let model = StudioModel(take: take, library: LibraryModel.shared)
        await model.load()
        if edited { model.edit { $0 = sampleProject(duration: $0.cuts.duration, edited: true) } }
        let chosen = options(size: size, noAudio: false)
        print("can save:", model.canSave(chosen))
        var finished = false
        model.save(options: chosen) { finished = true }
        while !finished && model.message.isEmpty {
            try? await Task.sleep(for: .milliseconds(300))
            if model.saveProgress == nil && !finished {
                try? await Task.sleep(for: .seconds(2))
                break
            }
        }
        print("finished:", finished, "message:", model.message.isEmpty ? "-" : model.message)
        return finished
    }
}

/// `Hot Take --splice-check Take.mp4` drives the Studio model the way the Video track's gestures do.
@MainActor
enum SpliceCheck {
    static func run(video: URL) async -> Bool {
        let directory = video.deletingLastPathComponent()
        guard let take = TakeLibrary.load(directory: directory).first(where: { $0.files.baseName == video.deletingPathExtension().lastPathComponent })
        else { print("take not found"); return false }
        let model = StudioModel(take: take, library: LibraryModel.shared)
        await model.load()
        var ok = true
        func check(_ name: String, _ condition: Bool) { print(condition ? "ok  " : "FAIL", name); if !condition { ok = false } }
        let total = model.project.outputDuration
        check("loaded a video of real length", total > 6)

        model.seek(to: 2); model.splice()
        model.seek(to: 4); model.splice()
        check("two splices make three parts and keep the length", model.project.cuts.partSpans.count == 3 && abs(model.project.outputDuration - total) < 1e-6)

        // Drag the first splice 1 s to the right, as the gesture does: from the project at the start of the drag.
        let base = model.project
        model.drag(.splice(afterPart: 0), from: base, by: 0.5)
        model.drag(.splice(afterPart: 0), from: base, by: 1.0)
        model.endGesture()
        let slid = model.project.cuts.segments
        check("dragging a splice slides it (2 → 3 s) without changing the length", abs(slid[0].end - 3) < 1e-6 && abs(slid[1].start - 3) < 1e-6 && abs(model.project.outputDuration - total) < 1e-6)

        model.undo()
        check("undo puts the splice back as one step", abs(model.project.cuts.segments[0].end - 2) < 1e-6)

        // Remove the middle part, then drag the first part's end back out to bring footage back.
        model.selectPart(atOutput: 3)
        check("clicking a part chooses it", model.selection == .range(TimeSpan(start: 2, end: 4)))
        model.deleteSelection()
        check("deleting the part shortens the video by its length", abs(model.project.outputDuration - (total - 2)) < 1e-6)
        let gapped = model.project
        model.drag(.edge(part: 0, edge: .end), from: gapped, by: 1.0)
        model.endGesture()
        check("dragging the edge beside the gap brings footage back", abs(model.project.outputDuration - (total - 1)) < 1e-6)
        model.undo()
        check("undo returns the gap", abs(model.project.outputDuration - (total - 2)) < 1e-6)

        // The video's own start: pull it in, then out again.
        let first = model.project
        model.drag(.edge(part: 0, edge: .start), from: first, by: 1.5)
        model.endGesture()
        check("dragging the start in trims it", abs(model.project.outputDuration - (first.outputDuration - 1.5)) < 1e-6)

        // Playhead keys
        model.undo()
        model.seek(to: 1); model.trimBeforePlayhead()
        check("[ drops the video before the playhead", abs(model.project.cuts.segments[0].start - 1) < 1e-6)
        return ok
    }
}
