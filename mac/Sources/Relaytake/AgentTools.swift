import AVFoundation
import AppKit
import CoreGraphics
import RelaytakeCore
import ScreenCaptureKit

// The commands that let an agent see and check what it is doing without a person in the loop: where the displays are, a
// picture of a screen taken without recording, a look at a screen before recording (which apps are on it and whether
// sensitive text is showing), pictures from a finished video, and a way to put away its own test takes. Everything runs on
// this Mac; pictures are written to private folders and nothing is sent anywhere.

extension RecorderModel {
    // MARK: Displays

    func agentDisplays() -> AgentResponse {
        AgentResponse(displays: Self.currentDisplays(), inputAllowed: AgentServer.inputAllowed)
    }

    static func currentDisplays() -> [AgentDisplay] {
        AgentDisplays.list(NSScreen.screens.map {
            AgentDisplays.Screen(name: $0.localizedName, frame: $0.frame, scale: Double($0.backingScaleFactor))
        })
    }

    /// The display a command is about: the one numbered, else the one Quick Record would use.
    private func agentDisplayTarget(_ number: Int?) -> (id: CGDirectDisplayID, number: Int)? {
        if let number {
            guard NSScreen.screens.indices.contains(number - 1), let id = NSScreen.screens[number - 1].displayID else { return nil }
            return (id, number)
        }
        guard let id = quickDisplay(), let index = NSScreen.screens.firstIndex(where: { $0.displayID == id }) else { return nil }
        return (id, index + 1)
    }

    private var agentHidesNotifications: Bool { UserDefaults.standard.object(forKey: Pref.hideNotifications) as? Bool ?? true }
    /// Pictures show what a recording would: Hot Take's own windows are in them only when "Show Hot Take in the recording" is on,
    /// which is how a demo of Hot Take itself can be seen.
    private var agentShowsHotTake: Bool { UserDefaults.standard.bool(forKey: Pref.includeOwnWindows) }

    // MARK: Screenshot and preflight

    func agentScreenshot(_ request: AgentRequest) async -> AgentResponse {
        guard let target = agentDisplayTarget(request.display) else {
            return .failure("There is no display \(request.display ?? 0). This Mac has \(NSScreen.screens.count).")
        }
        do {
            let image = try await ScreenshotTaker.capture(
                .display(target.id), hideNotifications: agentHidesNotifications, includeOwnApp: agentShowsHotTake)
            let scaled = AgentImages.scaled(image, maxWidth: max(200, min(4000, request.width ?? 1600)))
            let url = try AgentScratch.newPicture()
            try Screenshot.writePNG(scaled, to: url)
            return AgentResponse(image: url.path)
        } catch {
            return .failure("The screenshot could not be taken: \(error.localizedDescription). Screen Recording permission may be missing.")
        }
    }

    func agentPreflight(_ request: AgentRequest) async -> AgentResponse {
        guard let target = agentDisplayTarget(request.display) else {
            return .failure("There is no display \(request.display ?? 0). This Mac has \(NSScreen.screens.count).")
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let frame = content.displays.first { $0.displayID == target.id }?.frame ?? .null
            let own = agentShowsHotTake ? nil : Bundle.main.bundleIdentifier
            let apps = Set(content.windows.compactMap { window -> String? in
                guard window.isOnScreen, window.windowLayer == 0, window.frame.intersects(frame),
                      let app = window.owningApplication, app.bundleIdentifier != own, !app.applicationName.isEmpty
                else { return nil }
                return app.applicationName
            }).sorted()
            let image = try await ScreenshotTaker.capture(
                .display(target.id), hideNotifications: agentHidesNotifications, includeOwnApp: agentShowsHotTake)
            let terms = request.terms ?? []
            let sightings = try await Task.detached { try SensitiveScanJob.recognize(image, time: 0, terms: terms) }.value
            var warnings: [String] = []
            if !sightings.isEmpty {
                warnings.append("Text that looks sensitive is on display \(target.number). Clear it, move it to another display, or plan a blur before recording.")
            }
            if !apps.isEmpty {
                warnings.append("Windows from other apps are on display \(target.number): \(apps.joined(separator: ", ")). Anything they show will be in a recording of it.")
            }
            return AgentResponse(warnings: warnings.isEmpty ? nil : warnings, apps: apps, findings: sightings.map(AgentFinding.init))
        } catch {
            return .failure("The screen could not be checked: \(error.localizedDescription). Screen Recording permission may be missing.")
        }
    }

    // MARK: Pictures from a finished video

    func agentFrames(_ request: AgentRequest) async -> AgentResponse {
        let files: TakeFiles?
        if let name = request.take, !name.isEmpty {
            files = agentTake(named: name)
        } else if let rendered = lastAgentRender, FileManager.default.fileExists(atPath: rendered.video.path) {
            files = rendered
        } else {
            files = agentTake(named: nil)
        }
        guard let files else { return .failure("No recording found.") }
        let asset = AVURLAsset(url: files.video)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else {
            return .failure("That recording could not be read.")
        }
        let chapters = TakeLibrary.metadata(for: files)?.chapters.map(\.start) ?? []
        let times = AgentFrames.times(requested: request.times ?? [], chapterStarts: chapters, duration: duration)
        guard !times.isEmpty else { return .failure("There is nothing to take pictures of.") }

        let folder = files.framesDirectory
        try? FileManager.default.removeItem(at: folder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1440, height: 1440)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            var frames: [AgentFrame] = []
            var images: [(CGImage, String)] = []
            var sightings: [SensitiveSighting] = []
            let terms = request.terms ?? []
            for (index, time) in times.enumerated() {
                let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
                let url = folder.appendingPathComponent(AgentFrames.fileName(number: index + 1, of: times.count, time: time))
                try Screenshot.writePNG(image, to: url)
                frames.append(AgentFrame(time: time, path: url.path))
                images.append((image, NarrationScript.clock(time)))
                if request.scan == true {
                    sightings += try await Task.detached { try SensitiveScanJob.recognize(image, time: time, terms: terms) }.value
                }
            }
            var sheetPath: String?
            if let sheet = AgentContactSheet.make(images: images, columns: AgentFrames.columns(for: images.count)) {
                let url = folder.appendingPathComponent("Contact sheet.png")
                try Screenshot.writePNG(sheet, to: url)
                sheetPath = url.path
            }
            var warnings: [String] = []
            if request.scan == true {
                warnings.append(sightings.isEmpty
                    ? "Nothing sensitive was found in these \(frames.count) pictures. Small, blurry or briefly shown text can be missed, and only these moments were checked."
                    : "Text that looks sensitive appears in these pictures. Blur it or re-record before sharing.")
            }
            return AgentResponse(
                take: files.baseName, video: files.video.path, seconds: duration, warnings: warnings.isEmpty ? nil : warnings,
                findings: request.scan == true ? sightings.map(AgentFinding.init) : nil, frames: frames, contactSheet: sheetPath)
        } catch {
            return .failure("The pictures could not be made: \(error.localizedDescription)")
        }
    }

    // MARK: Cleaning up

    /// Moves a take an agent recorded (or a copy it saved) to the Trash. It will not touch a take a person recorded.
    func agentDiscard(_ request: AgentRequest) async -> AgentResponse {
        guard let name = request.take, !name.isEmpty else { return .failure("discard needs the name of the take. It will not guess.") }
        LibraryModel.shared.refresh()
        guard let entry = LibraryModel.shared.takes.first(where: { $0.files.baseName == name || $0.id == name }) else {
            return .failure("No recording is named “\(name)”.")
        }
        let files = entry.files
        guard FileManager.default.fileExists(atPath: files.markers.path) else {
            return .failure("“\(name)” was not recorded by an agent, so Hot Take will not discard it. Move it to the Trash yourself.")
        }
        if current?.files == files, phase != .idle { return .failure("That take is still being recorded.") }
        if StudioModel.isOpen(files) { return .failure("That take is open in the Studio. Close it first.") }
        do {
            try TakeLibrary.trash(entry)
            try? FileManager.default.removeItem(at: files.framesDirectory)
            if lastAgentTake == files { lastAgentTake = nil }
            if lastAgentRender == files { lastAgentRender = nil }
            LibraryModel.shared.refresh()
            return AgentResponse(discarded: [files.baseName])
        } catch {
            return .failure("Could not move it to the Trash: \(error.localizedDescription)")
        }
    }

    // MARK: Window

    /// Puts the library window on a display, large and centered, so a demo happens on the screen being recorded.
    func agentMoveWindow(display: Int?) async -> AgentResponse {
        guard let target = agentDisplayTarget(display), let screen = NSScreen.screens.first(where: { $0.displayID == target.id }) else {
            return .failure("There is no display \(display ?? 0). This Mac has \(NSScreen.screens.count).")
        }
        func mainWindow() -> NSWindow? {
            NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && $0.canBecomeMain }
        }
        if mainWindow() == nil {
            libraryRequest += 1
            for _ in 0..<20 where mainWindow() == nil { try? await Task.sleep(for: .milliseconds(100)) }
        }
        guard let window = mainWindow() else { return .failure("Hot Take has no window open to move.") }
        let area = screen.visibleFrame
        window.setFrame(area.insetBy(dx: area.width * 0.04, dy: area.height * 0.04), display: true, animate: false)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return AgentResponse(displays: Self.currentDisplays())
    }
}

/// Where an agent's screenshots go: a private folder, cleared of anything older than a day each time one is added.
enum AgentScratch {
    static let maximumAge: TimeInterval = 24 * 3600

    static func newPicture(fileManager: FileManager = .default) throws -> URL {
        let folder = AgentPaths.directory().appendingPathComponent("screenshots", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let cutoff = Date().addingTimeInterval(-maximumAge)
        for url in (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
            if modified < cutoff { try? fileManager.removeItem(at: url) }
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: ".")
        return folder.appendingPathComponent("Screen \(stamp) \(UUID().uuidString.prefix(4)).png")
    }
}

enum AgentImages {
    /// The picture scaled down to `maxWidth` pixels wide (never up).
    static func scaled(_ image: CGImage, maxWidth: Int) -> CGImage {
        guard image.width > maxWidth else { return image }
        let height = max(1, Int((Double(image.height) * Double(maxWidth) / Double(image.width)).rounded()))
        guard let context = CGContext(
            data: nil, width: maxWidth, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
        return context.makeImage() ?? image
    }
}

/// All the pictures together on one sheet, each labeled with its time, so an agent can look at a whole video in one go.
enum AgentContactSheet {
    static func make(images: [(image: CGImage, label: String)], columns: Int, cellWidth: Int = 640) -> CGImage? {
        guard !images.isEmpty, columns > 0 else { return nil }
        let gap = 12, labelHeight = 26
        let cellHeight = cellWidth * 9 / 16
        let rows = (images.count + columns - 1) / columns
        let width = columns * cellWidth + (columns + 1) * gap
        let height = rows * (cellHeight + labelHeight) + (rows + 1) * gap
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        for (index, item) in images.enumerated() {
            let column = index % columns, row = index / columns
            let x = gap + column * (cellWidth + gap)
            // CoreGraphics measures from the bottom, so the first row is at the top.
            let top = height - gap - row * (cellHeight + labelHeight + gap)
            let cell = CGRect(x: x, y: top - cellHeight, width: cellWidth, height: cellHeight)
            let scale = min(Double(cell.width) / Double(item.image.width), Double(cell.height) / Double(item.image.height))
            let size = CGSize(width: Double(item.image.width) * scale, height: Double(item.image.height) * scale)
            context.draw(item.image, in: CGRect(
                x: cell.midX - size.width / 2, y: cell.midY - size.height / 2, width: size.width, height: size.height))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            let text = "\(index + 1)  ·  \(item.label)" as NSString
            text.draw(
                at: CGPoint(x: Double(x), y: Double(top - cellHeight - labelHeight + 5)),
                withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white])
            NSGraphicsContext.restoreGraphicsState()
        }
        return context.makeImage()
    }
}
