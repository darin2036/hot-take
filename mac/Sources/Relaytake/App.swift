import AVFoundation
import OSLog
import AppKit
import CoreGraphics
import PlainspokenSpeech
import RelaytakeCore
import ScreenCaptureKit
import SwiftUI

@MainActor
final class RecorderModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording(since: Date)
        case saving
        case processing(String)
    }

    @Published var phase: Phase = .idle
    @Published var message = ""
    /// True while the "what do you want to record?" sheet is showing.
    @Published var choosing = false
    /// Bumped to ask the always-alive menu-bar label to open the library window.
    @Published var libraryRequest = 0
    /// Good news to show for a while (a saved screenshot), and the file it is about.
    @Published var notice = ""
    @Published var noticeFile: URL?
    /// The bug report being reviewed, shown as a sheet over the library.
    @Published var bugReportSession: BugReportSession?

    /// The one recorder the app runs, for library tools that report through its status banner.
    private(set) static weak var current: RecorderModel?

    // Edited in SettingsView; read here when a recording starts or finishes.
    func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    /// "No audio" in the record sheet silences both the microphone and the computer's sound.
    private var silent: Bool { UserDefaults.standard.bool(forKey: Pref.noAudio) }

    private let recorder = ScreenRecorder()
    private let clickRecorder = ClickRecorder()
    /// The camera used by the record sheet's preview and then by the recording itself.
    let camera = CameraSession()
    /// Seconds from the screen's first frame to the camera's first frame, when a camera is being recorded.
    private var cameraOffset: Double?
    private var restarting = false
    /// True while a take is paused. Paused time is left out of the take and of its click timings.
    @Published private(set) var paused = false
    private var takeOptions: TakeOptions?
    /// The pieces of the take in order: a pause ends one piece and a resume starts the next.
    private var screenPieces: [URL] = []
    private var cameraPieces: [URL] = []
    private var cameraFinishedCleanly = false
    private var takeStart = Date()
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    private var pausedPlacement: CameraPlacement?
    /// The number the next piece of the take is given. It only counts up, so a rewind never reuses a number.
    private var nextPiece = 1
    /// True while the end of the take is being cut off for a rewind.
    @Published private(set) var rewinding = false
    /// How far Rewind goes back, in seconds.
    nonisolated static let rewindSeconds = 10.0
    /// The end of a pause or resume that is still stopping or starting the capture.
    private var transition: Task<Void, Never>?

    private struct TakeOptions {
        var target: RecordingTarget
        var microphone: Bool
        var microphoneID: String
        var systemAudio: Bool
        var keepWindows: Bool
        var useCamera: Bool
        var hideNotifications: Bool
    }

    /// A take of the camera alone: the camera's picture and the microphone's sound, recorded separately and put
    /// together when it stops.
    private struct CameraOnlyTake {
        var files: TakeFiles
        var created: Date
        var cameraFile: URL
        var cameraStart: Date
        var microphone: MicrophoneRecorder?
        var micFile: URL?
        var micStart: Date?
    }
    private var cameraOnly: CameraOnlyTake?

    /// Whether Pause does anything for this take (a camera-only take cannot be paused).
    var canPause: Bool { takeOptions != nil }

    private var hideNotifications: Bool { flag(Pref.hideNotifications) }

    /// Time recorded so far, not counting paused time.
    func elapsed(at date: Date) -> TimeInterval {
        max(0, (pausedAt ?? date).timeIntervalSince(takeStart) - pausedTotal)
    }
    private var lastTarget: RecordingTarget?
    private var contentPicker: ContentPicker?
    private var regionSelector: RegionSelector?
    private var current: (files: TakeFiles, created: Date)?
    /// New takes go into the folder being viewed in the library.
    var directory: URL { directoryOverride ?? LibraryModel.shared.recordingDirectory }
    /// Used by the `--record-check` test mode to keep its take out of the library.
    var directoryOverride: URL?

    init() {
        Self.current = self
        watchForUnexpectedStop()
        // Shortcuts that work in any app.
        GlobalHotkeys.shared.onTrigger = { [weak self] action in self?.handle(action) }
        GlobalHotkeys.shared.refresh()
    }

    // MARK: Shortcuts and quick capture

    func handle(_ action: HotkeyAction) {
        switch action {
        case .startStop:
            if isRecording { toggle() } else { quickRecord() }
        case .startAgent:
            if isRecording { toggle() } else { quickRecordForAgent() }
        case .pause:
            if isRecording, canPause { paused ? resume() : pause() }
        case .rewind:
            rewind()
        case .screenshot:
            quickScreenshot()
        }
    }

    /// The display Quick Record and screenshots use: the one recorded last if it is still there, else the main one.
    private func quickDisplay() -> CGDirectDisplayID? {
        let last = UserDefaults.standard.object(forKey: Pref.lastDisplay) as? Int
        return QuickCapturePlan.display(
            last: last.flatMap { UInt32(exactly: $0) }, connected: NSScreen.screens.compactMap(\.displayID), main: NSScreen.main?.displayID)
    }

    /// Starts recording a whole screen right away with the settings used last, after the usual countdown. No sheet.
    func quickRecord() {
        guard phase == .idle else { return }
        guard let display = quickDisplay() else { message = "No display was found to record."; return }
        begin(.screen(display))
    }

    /// Quick Record for this take only: when it stops, it is also turned into a request for a coding agent, whatever
    /// the "For an agent" checkbox says. The checkbox itself is left as it was.
    func quickRecordForAgent() {
        guard phase == .idle else { return }
        guard let display = quickDisplay() else { message = "No display was found to record."; return }
        begin(.screen(display), forAgent: true)
    }

    /// Set by a Quick Take for Agent and reset by every new take, so a take that never started cannot leak into the next.
    private var quickAgent = false

    func quickScreenshot() {
        guard phase == .idle, let display = quickDisplay() else { return }
        takeScreenshot(.screen(display))
    }

    /// Saves a PNG of a screen, window or area into the folder being viewed.
    func takeScreenshot(_ choice: SourceChoice) {
        guard phase == .idle else { return }
        choosing = false
        message = ""
        notice = ""
        guard ensureScreenPermission() else { return }
        phase = .processing("Taking a screenshot…")
        Task {
            defer { phase = .idle }
            do {
                let target: RecordingTarget?
                switch choice {
                case .screen(let id): target = .display(id)
                case .window(let filter): target = .window(filter)
                case .windowOrApp:
                    let picker = ContentPicker()
                    contentPicker = picker
                    let filter = await picker.pick()
                    contentPicker = nil
                    target = filter.map { .window($0) }
                case .area:
                    // Out of the way so the whole screen can be picked from. Hot Take itself is never in the picture.
                    minimizeWindows()
                    let selector = RegionSelector()
                    regionSelector = selector
                    let selection = await selector.select()
                    regionSelector = nil
                    restoreWindows()
                    target = selection.map { .region(display: $0.displayID, rect: $0.rect) }
                case .camera: target = nil
                }
                guard let target else { return }
                // Let the sheet or the picker finish leaving the screen before looking at it.
                try? await Task.sleep(for: .milliseconds(250))
                let image = try await ScreenshotTaker.capture(target, hideNotifications: hideNotifications)
                let url = Screenshot.uniqueURL(in: directory, for: Date())
                try Screenshot.writePNG(image, to: url)
                if case .display(let id) = target { UserDefaults.standard.set(Int(id), forKey: Pref.lastDisplay) }
                noticeFile = url
                notice = "Saved the screenshot “\(url.lastPathComponent)”."
            } catch {
                message = "Could not take the screenshot: \(error.localizedDescription)"
            }
        }
    }

    func clearNotice() { notice = ""; noticeFile = nil }

    var isRecording: Bool { if case .recording = phase { true } else { false } }
    var isBusy: Bool { if case .idle = phase { false } else if isRecording { false } else { true } }

    /// New Take opens the source chooser; while recording it stops.
    func toggle() {
        if isRecording {
            Task { await stop() }
        } else if case .idle = phase {
            choosing = true
            libraryRequest += 1  // make sure the window that hosts the sheet is up
        }
    }

    enum SourceChoice {
        case screen(CGDirectDisplayID)
        case windowOrApp
        /// A window chosen from the previews in the record sheet.
        case window(SCContentFilter)
        case area
        /// The camera on its own, with the microphone, and no screen.
        case camera
    }

    func begin(_ choice: SourceChoice, forAgent: Bool = false) {
        guard phase == .idle else { return }
        quickAgent = forAgent
        choosing = false
        message = ""
        if case .camera = choice { beginCameraOnly(); return }
        guard ensureScreenPermission() else { return }
        phase = .processing("Choosing source…")
        Task {
            defer { if !isRecording { phase = .idle } }
            switch choice {
            case .screen(let id):
                await start(target: .display(id))
            case .window(let filter):
                await start(target: .window(filter))
            case .windowOrApp:
                let picker = ContentPicker()
                contentPicker = picker
                let filter = await picker.pick()
                contentPicker = nil
                if let filter { await start(target: .window(filter)) }
            case .camera:
                break  // handled before the screen is asked for
            case .area:
                if !UserDefaults.standard.bool(forKey: Pref.includeOwnWindows) { minimizeWindows() }  // so the whole screen is visible to select from
                let selector = RegionSelector()
                regionSelector = selector
                let selection = await selector.select()
                regionSelector = nil
                if let selection {
                    await start(target: .region(display: selection.displayID, rect: selection.rect))
                } else {
                    restoreWindows()
                }
            }
        }
    }

    /// Ask the system once, then explain. Calling ScreenCaptureKit without permission re-prompts every time.
    private func ensureScreenPermission() -> Bool {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            message = "Hot Take needs Screen Recording permission. Turn it on in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen Hot Take."
            return false
        }
        return true
    }

    /// Whether the recording will contain Hot Take's own windows, so they must stay on screen.
    private func recordsSelf(_ target: RecordingTarget) -> Bool {
        switch target {
        case .display, .region: UserDefaults.standard.bool(forKey: Pref.includeOwnWindows)
        case .window(let filter): filter.includedApplications.contains { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        }
    }

    private var recordingQuality = EncodingSettings(preset: .medium)

    private func start(target: RecordingTarget) async {
        recordingQuality = EncodingPreferences.resolve(VideoQuality(rawValue: UserDefaults.standard.string(forKey: Pref.quality) ?? "medium") ?? .medium)
        lastTarget = target
        switch target {
        case .display(let id), .region(let id, _): UserDefaults.standard.set(Int(id), forKey: Pref.lastDisplay)
        case .window: break
        }
        phase = .processing("Starting recording…")
        let microphone = flag(Pref.microphone) && !silent
        let microphoneID = UserDefaults.standard.string(forKey: Pref.microphoneDevice) ?? ""
        let systemAudio = flag(Pref.systemAudio) && !silent
        if microphone && AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        let screens: [NSScreen]
        switch target {
        case .display(let id), .region(let id, _):
            screens = NSScreen.screens.filter { $0.displayID == id }
        case .window:
            screens = NSScreen.screens
        }
        let cameraID = UserDefaults.standard.string(forKey: Pref.cameraDevice) ?? ""
        var useCamera = !cameraID.isEmpty && camera.isAuthorized
        if useCamera { useCamera = await camera.configure(cameraID: cameraID) }
        if useCamera { camera.startPreview() }  // warms up during the countdown
        // Your circle appears with the countdown, so you can see yourself and move it before recording begins. It goes on the
        // camera now because adding it to a session that is already recording stalls the recording.
        if useCamera, let area = SelfViewPanel.area(for: target) {
            SelfViewPanel.shared.show(camera: camera, over: area, placement: nil, size: PresenterSize.current.fraction)
        }
        cameraOffset = nil
        let keepWindows = recordsSelf(target)
        if !keepWindows { minimizeWindows() }
        RecordingPanel.shared.hide()
        let completed = await RecordingCountdown().run(on: screens)
        guard completed else {
            SelfViewPanel.shared.hide()
            camera.stopPreview()
            phase = .idle
            restoreWindows()
            return
        }
        let created = Date()
        let files = TakeFiles(directory: directory, baseName: TakeFiles.baseName(for: created))
        message = ""
        // The camera starts first. It is already warm from the countdown, and starting it after the screen leaves the first
        // moments of the video without your circle. Anything it records before the screen begins is trimmed off with the offset.
        let cameraStart: Date? = useCamera ? await camera.record(to: files.cameraOriginal) : nil
        do {
            try await recorder.start(to: files.video, target: target, microphone: microphone, microphoneID: microphoneID,
                                      systemAudio: systemAudio, includeOwnWindows: keepWindows, hideNotifications: hideNotifications, quality: recordingQuality)
            current = (files, created)
            takeOptions = TakeOptions(target: target, microphone: microphone, microphoneID: microphoneID, systemAudio: systemAudio,
                                      keepWindows: keepWindows, useCamera: useCamera, hideNotifications: hideNotifications)
            takeStart = recorder.startedAt ?? Date()
            screenPieces = [files.video]
            cameraPieces = []
            nextPiece = 1
            pausedTotal = 0
            pausedAt = nil
            paused = false
            if let cameraStart, let screenStart = recorder.startedAt {
                cameraOffset = cameraStart.timeIntervalSince(screenStart)
                cameraPieces = [files.cameraOriginal]
                cameraFinishedCleanly = false
            } else if useCamera {
                if cameraStart != nil { _ = await camera.finish() }
                message = "The camera did not start, so this take has the screen only."
                SelfViewPanel.shared.hide()
                camera.stopPreview()
            }
            clickRecorder.start(target: target, startedAt: takeStart)
            phase = .recording(since: created)
            if !keepWindows { minimizeWindows() }
            RecordingPanel.shared.show(model: self)
        } catch {
            message = "Could not start: \(error.localizedDescription)"
            if cameraStart != nil {
                _ = await camera.finish()
                try? FileManager.default.removeItem(at: files.cameraOriginal)
            }
            SelfViewPanel.shared.hide()
            camera.stopPreview()
            phase = .idle
            restoreWindows()
        }
    }

    /// Discards the current take (to the Trash) and immediately starts a fresh one.
    /// Throws away the take in progress and starts a fresh one with a new countdown. Ignored while a restart is already
    /// underway, so a double click cannot start two.
    func restart() {
        guard isRecording, !restarting, let current else { return }
        if cameraOnly != nil { restartCameraOnly(); return }
        restarting = true
        Task {
            defer { restarting = false }
            phase = .processing("Restarting…")
            await transition?.value
            _ = try? await recorder.stop()
            if cameraOffset != nil { _ = await camera.finish() }
            SelfViewPanel.shared.hide()
            cameraOffset = nil
            for piece in screenPieces.dropFirst() + cameraPieces.dropFirst() { try? FileManager.default.removeItem(at: piece) }
            try? FileManager.default.trashItem(at: current.files.video, resultingItemURL: nil)
            try? FileManager.default.removeItem(at: current.files.cameraOriginal)
            self.current = nil
            takeOptions = nil
            paused = false
            pausedAt = nil
            phase = .idle
            if let target = lastTarget { await start(target: target) }
            if !isRecording { RecordingPanel.shared.hide(); restoreWindows() }
        }
    }

    /// Ends the current piece of the take. Nothing is recorded until resume, and that time is left out.
    func pause() {
        guard isRecording, !paused, let options = takeOptions else { return }
        paused = true
        pausedAt = Date()
        clickRecorder.stop()
        // The camera stays on during a pause, with your circle still showing, so resuming is instant.
        let previous = transition
        transition = Task {
            await previous?.value
            await endPiece(options)
        }
    }

    private func endPiece(_ options: TakeOptions) async {
        _ = try? await recorder.stop()
        if options.useCamera { cameraFinishedCleanly = await camera.finish(keepRunning: true) }
    }

    /// Whether Rewind can be used now: a take that can be paused, long enough to go back in, and not already rewinding.
    var canRewind: Bool { isRecording && canPause && !rewinding && !restarting }

    /// Goes back `seconds` in the take and pauses there. The footage after that point is thrown away, so you can say it
    /// again: Resume carries on from the new end. Each pause already ends a piece of the take, so this ends the piece being
    /// recorded, then drops whole pieces from the end and cuts the one it lands in. Clicks after that point go too.
    func rewind(seconds: Double = RecorderModel.rewindSeconds) {
        guard canRewind, let options = takeOptions else { return }
        rewinding = true
        if !paused {
            paused = true
            pausedAt = Date()
            clickRecorder.stop()
        }
        let previous = transition
        transition = Task {
            await previous?.value
            // A resume that was still starting when Rewind was pressed has finished by now, so end its piece too.
            if !paused { paused = true; pausedAt = Date(); clickRecorder.stop(); await endPiece(options) }
            await cutBack(by: seconds)
            rewinding = false
        }
    }

    /// Cuts the screen and camera pieces back to the take's length minus `seconds`.
    private func cutBack(by seconds: Double) async {
        var screenLengths: [Double] = []
        for piece in screenPieces { screenLengths.append(await SegmentJoiner.length(of: piece)) }
        guard let keep = RewindPlan.keepTime(total: screenLengths.reduce(0, +), rewind: seconds),
              let plan = RewindPlan.make(durations: screenLengths, keep: keep) else {
            message = "There is not enough recorded yet to rewind."
            return
        }
        do {
            if let length = plan.lastLength {
                try await SegmentJoiner.trim(screenPieces[plan.keptPieces - 1], to: length, as: .mp4)
            }
        } catch {
            message = "Could not rewind: \(error.localizedDescription)"
            return
        }
        for piece in screenPieces[plan.keptPieces...] { try? FileManager.default.removeItem(at: piece) }
        screenPieces.removeLast(screenPieces.count - plan.keptPieces)

        // The camera started a little before the screen did, so it keeps that much more.
        if !cameraPieces.isEmpty {
            var cameraLengths: [Double] = []
            for piece in cameraPieces { cameraLengths.append(await SegmentJoiner.length(of: piece)) }
            if let cameraPlan = RewindPlan.make(durations: cameraLengths, keep: keep + (cameraOffset ?? 0)) {
                do {
                    if let length = cameraPlan.lastLength {
                        try await SegmentJoiner.trim(cameraPieces[cameraPlan.keptPieces - 1], to: length, as: .mov)
                    }
                    for piece in cameraPieces[cameraPlan.keptPieces...] { try? FileManager.default.removeItem(at: piece) }
                    cameraPieces.removeLast(cameraPieces.count - cameraPlan.keptPieces)
                } catch {
                    message = "The screen was rewound but the camera could not be, so it may be a little out of step: \(error.localizedDescription)"
                }
            }
        }
        // The timer and the click timings go back with the footage.
        if let stoppedAt = pausedAt { pausedTotal += max(0, elapsed(at: stoppedAt) - keep) }
        clickRecorder.drop(after: keep)
    }

    /// Starts the next piece of the take, with the time paused left out.
    func resume() {
        guard paused, let options = takeOptions, let current, let stoppedAt = pausedAt else { return }
        let previous = transition
        transition = Task {
            await previous?.value
            let number = nextPiece
            nextPiece += 1
            let video = current.files.pieceURL(number: number, extension: "mp4")
            do {
                let resumedAt = Date()
                try await recorder.start(to: video, target: options.target, microphone: options.microphone, microphoneID: options.microphoneID,
                                         systemAudio: options.systemAudio, includeOwnWindows: options.keepWindows,
                                         hideNotifications: options.hideNotifications, quality: recordingQuality)
                screenPieces.append(video)
                pausedTotal += resumedAt.timeIntervalSince(stoppedAt)
                pausedAt = nil
                paused = false
                clickRecorder.resume(target: options.target, startedAt: takeStart.addingTimeInterval(pausedTotal))
                if options.useCamera {
                    let clip = current.files.pieceURL(number: number, extension: "mov")
                    if await camera.record(to: clip) != nil {
                        cameraPieces.append(clip)
                    } else {
                        message = "The camera did not restart, so the rest of this take has the screen only. \(camera.problem)"
                    }
                }
            } catch {
                message = "Could not carry on after the pause: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Camera-only takes

    private func beginCameraOnly() {
        guard phase == .idle else { return }
        phase = .processing("Starting the camera…")
        Task {
            defer { if !isRecording { phase = .idle } }
            await startCameraOnly()
        }
    }

    /// Records the camera and the microphone, with no screen, after the usual countdown. The two files are
    /// put together when it stops.
    private func startCameraOnly() async {
        let cameraID = UserDefaults.standard.string(forKey: Pref.cameraDevice) ?? ""
        await camera.requestAccess()
        guard camera.isAuthorized else {
            message = "Camera access is off. Turn it on in System Settings → Privacy & Security → Camera."
            return
        }
        guard !cameraID.isEmpty, await camera.configure(cameraID: cameraID) else {
            message = cameraID.isEmpty ? "Choose a camera in the record sheet first." : "That camera is not available. \(camera.problem)"
            return
        }
        let wantsMicrophone = flag(Pref.microphone) && !silent
        if wantsMicrophone, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        camera.startPreview()  // warms up during the countdown
        phase = .processing("Starting recording…")
        guard await RecordingCountdown().run(on: NSScreen.main.map { [$0] } ?? []) else {
            camera.stopPreview()
            return
        }
        let created = Date()
        let files = TakeFiles(directory: directory, baseName: TakeFiles.baseName(for: created))
        let cameraFile = files.pieceURL(number: 0, extension: "mov")
        var microphone: MicrophoneRecorder?
        var micFile: URL?
        var micStart: Date?
        if wantsMicrophone, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            let choice = Microphone.chosen(id: UserDefaults.standard.string(forKey: Pref.microphoneDevice) ?? "")
            let file = files.pieceURL(number: 0, extension: "m4a")
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let recorder = MicrophoneRecorder(url: file)
            do {
                try recorder.start(device: choice.device)
                microphone = recorder
                micFile = file
                micStart = Date()
            } catch {
                message = "The microphone did not start, so this take has no sound. \(error.localizedDescription)"
            }
        }
        guard let cameraStart = await camera.record(to: cameraFile) else {
            microphone?.discard()
            camera.stopPreview()
            message = "The camera did not start. \(camera.problem)"
            return
        }
        cameraOnly = CameraOnlyTake(
            files: files, created: created, cameraFile: cameraFile, cameraStart: cameraStart,
            microphone: microphone, micFile: micFile, micStart: micStart)
        current = (files, created)
        phase = .recording(since: created)
        RecordingPanel.shared.show(model: self)
    }

    private func restartCameraOnly() {
        guard let take = cameraOnly else { return }
        restarting = true
        Task {
            defer { restarting = false }
            phase = .processing("Restarting…")
            take.microphone?.discard()
            _ = await camera.finish()
            for file in [take.cameraFile, take.micFile].compactMap({ $0 }) { try? FileManager.default.removeItem(at: file) }
            cameraOnly = nil
            current = nil
            RecordingPanel.shared.hide()
            phase = .idle
            await startCameraOnly()
            if !isRecording { phase = .idle }
        }
    }

    private func finishCameraOnly(_ take: CameraOnlyTake) async {
        phase = .saving
        RecordingPanel.shared.hide()
        let micFile = await take.microphone?.stop()
        let cameraFinished = await camera.finish()
        RecordingSounds.shared.play(.ended)
        cameraOnly = nil
        current = nil
        func cleanUp() {
            for file in [take.cameraFile, take.micFile].compactMap({ $0 }) { try? FileManager.default.removeItem(at: file) }
        }
        let usable = cameraFinished ? true : await Self.hasFootage(take.cameraFile)
        guard usable else {
            message = "The camera recording could not be saved. \(camera.problem)"
            cleanUp()
            phase = .idle
            return
        }
        phase = .processing("Saving the camera take…")
        // The microphone began a moment before or after the camera's first picture; line the sound up with it.
        let delay = take.micStart.map { $0.timeIntervalSince(take.cameraStart) } ?? 0
        do {
            try await CameraOnlyMixer.merge(video: take.cameraFile, audio: micFile, audioDelay: delay, to: take.files.video)
        } catch {
            message = error.localizedDescription
            cleanUp()
            phase = .idle
            return
        }
        cleanUp()
        try? TakeLibrary.saveCapture(for: take.files, created: take.created, clicks: [], kind: "camera")
        LibraryModel.shared.refresh()
        let options = Pipeline.Options(captions: flag(Pref.captions), summary: flag(Pref.summary))
        let notes = await Pipeline.process(take: take.files, created: take.created, options: options) { [weak self] text in
            self?.phase = .processing(text)
        }
        if !notes.isEmpty { message = notes.joined(separator: "\n") }
        LibraryModel.shared.select(files: take.files)
        libraryRequest += 1
        phase = .idle
        LibraryModel.shared.refresh()
    }

    /// Tuck the main window away while recording; the control bar stays on top.
    private func minimizeWindows() {
        let visible = NSApp.windows.filter { !($0 is NSPanel) && $0.isVisible && $0.canBecomeMain }
        visible.forEach { $0.miniaturize(nil) }
        hiddenWindows += visible
    }

    private func restoreWindows() {
        hiddenWindows.forEach { $0.deminiaturize(nil) }
        hiddenWindows = []
    }

    private var hiddenWindows: [NSWindow] = []

    private func stop() async {
        if let take = cameraOnly { await finishCameraOnly(take); return }
        guard let current else { return }
        let forAgent = quickAgent || UserDefaults.standard.bool(forKey: Pref.recordForAgent)
        quickAgent = false
        // Where the time goes after Stop, in the system log (subsystem org.relaytake.mac, category save). It stays on this Mac.
        let saveLog = Logger(subsystem: "org.relaytake.mac", category: "save")
        var mark = Date()
        func lap(_ stage: String) {
            saveLog.info("\(stage, privacy: .public): \(Date().timeIntervalSince(mark), format: .fixed(precision: 2)) s")
            mark = Date()
        }
        phase = .saving
        RecordingPanel.shared.hide()
        restoreWindows()
        let clicks = clickRecorder.stop()
        await transition?.value
        let wasPaused = paused
        paused = false
        if !wasPaused {
            do { _ = try await recorder.stop() } catch {
                message = "Recording ended with an error: \(error.localizedDescription)"
            }
        }
        lap("screen recording closed")
        let placement = SelfViewPanel.shared.placement() ?? pausedPlacement
        if !wasPaused, takeOptions?.useCamera == true { cameraFinishedCleanly = await camera.finish() }
        RecordingSounds.shared.play(.ended)
        SelfViewPanel.shared.hide()
        var cameraRecorded = cameraOffset != nil && cameraFinishedCleanly
        if cameraOffset != nil, !cameraRecorded {
            // The system's "finished" report is not the last word: if the file has footage, use it.
            if await Self.hasFootage(current.files.cameraOriginal) {
                cameraRecorded = true
            } else {
                message = "Your camera recording could not be saved, so this take has the screen only. \(camera.problem)"
            }
        }
        lap(cameraRecorded ? "camera closed" : "camera closed (not usable)")
        await joinPieces(for: current.files)
        lap("paused pieces joined")
        // With a camera, the camera is drawn into the take below, which also makes the file smaller. Without one, shrink it here.
        if !cameraRecorded { await reduceSize(of: current.files.video); lap("file size reduced") }
        var bakedCameraOffset: Double?
        if cameraRecorded, let offset = cameraOffset, FileManager.default.fileExists(atPath: current.files.video.path) {
            phase = .processing("Adding your camera…")
            if await bakeCamera(into: current.files, offset: offset, placement: placement) { bakedCameraOffset = offset }
            else { await reduceSize(of: current.files.video) }
            lap("camera added")
        }
        if bakedCameraOffset == nil { try? FileManager.default.removeItem(at: current.files.cameraOriginal) }
        cameraOffset = nil
        takeOptions = nil
        screenPieces = []
        cameraPieces = []
        pausedPlacement = nil
        // What was seen while recording (clicks for auto-zoom, and what was captured) goes beside the video.
        if FileManager.default.fileExists(atPath: current.files.video.path) {
            try? TakeLibrary.saveCapture(
                for: current.files, created: current.created, clicks: clicks,
                kind: lastTarget.map(ClickRecorder.kind(of:)) ?? "screen", cameraOffset: bakedCameraOffset,
                cameraPlacement: bakedCameraOffset == nil ? nil : placement)
        }
        LibraryModel.shared.refresh()

        let options = Pipeline.Options(captions: flag(Pref.captions), summary: flag(Pref.summary))
        if FileManager.default.fileExists(atPath: current.files.video.path) {
            let notes = await Pipeline.process(
                take: current.files, created: current.created, options: options
            ) { [weak self] text in self?.phase = .processing(text) }
            if !notes.isEmpty { message = notes.joined(separator: "\n") }
            LibraryModel.shared.select(files: current.files)
            libraryRequest += 1
            lap("captions and summary")
            if forAgent {
                await handOffToAgent(current.files)
                lap("request for an agent")
            }
        }
        self.current = nil
        phase = .idle
        LibraryModel.shared.refresh()
    }

    /// Whether a camera file has at least a moment of picture in it.
    private static func hasFootage(_ url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isNumeric, duration.seconds > 0.5 else { return false }
        return ((try? await asset.loadTracks(withMediaType: .video)) ?? []).isEmpty == false
    }

    /// Joins the pieces of a paused take into one screen file and one camera file. A take that was never paused has one piece.
    private func joinPieces(for files: TakeFiles) async {
        let staging = files.directory.appendingPathComponent(".relaytake-processing", isDirectory: true)
        if screenPieces.count > 1 {
            phase = .processing("Joining the paused take…")
            let joined = staging.appendingPathComponent("\(UUID().uuidString).mp4")
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                try await SegmentJoiner.join(screenPieces, to: joined, as: .mp4)
                _ = try FileManager.default.replaceItemAt(files.video, withItemAt: joined)
            } catch { message = "Could not join the paused take: \(error.localizedDescription)" }
            try? FileManager.default.removeItem(at: joined)
            for piece in screenPieces.dropFirst() { try? FileManager.default.removeItem(at: piece) }
        }
        if cameraPieces.count > 1 {
            let joined = staging.appendingPathComponent("\(UUID().uuidString).mov")
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                try await SegmentJoiner.join(cameraPieces, to: joined, as: .mov)
                _ = try FileManager.default.replaceItemAt(files.cameraOriginal, withItemAt: joined)
            } catch { message = "Could not join the camera for the paused take: \(error.localizedDescription)" }
            try? FileManager.default.removeItem(at: joined)
            for piece in cameraPieces.dropFirst() { try? FileManager.default.removeItem(at: piece) }
        }
    }

    /// Re-encodes a recording at the chosen file size, if that makes it smaller. Keeps the original if anything fails.
    private func reduceSize(of video: URL) async {
        guard FileManager.default.fileExists(atPath: video.path) else { return }
        phase = .processing("Reducing file size…")
        let staging = video.deletingLastPathComponent().appendingPathComponent(".relaytake-processing", isDirectory: true)
        let optimized = staging.appendingPathComponent("\(UUID().uuidString).mp4")
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try await Compressor.save(asset: AVURLAsset(url: video), to: optimized, quality: recordingQuality) { _ in }
            let oldSize = try video.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let newSize = try optimized.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if newSize > 0, newSize < oldSize {
                _ = try FileManager.default.replaceItemAt(video, withItemAt: optimized)
            }
        } catch { message = "Saved the recording without size optimization: \(error.localizedDescription)" }
        try? FileManager.default.removeItem(at: optimized)
    }

    /// Draws the camera into the take in its default corner, and keeps the plain screen recording beside it so the
    /// Studio can move, resize or hide the camera later. If anything goes wrong the take stays screen-only.
    private func bakeCamera(into files: TakeFiles, offset: Double, placement: CameraPlacement?) async -> Bool {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: files.originalsDirectory, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: files.screenOriginal)
            try fileManager.moveItem(at: files.video, to: files.screenOriginal)
        } catch { message = "Saved the recording without the camera: \(error.localizedDescription)"; return false }
        do {
            let asset = AVURLAsset(url: files.screenOriginal)
            let duration = try await asset.load(.duration).seconds
            let project = StudioProject(duration: duration, cameraSource: CameraSource(url: files.cameraOriginal, offset: offset, placement: placement))
            try await StudioSaver.render(asset: asset, project: project, to: files.video, format: .mp4,
                                          options: StudioSaveOptions(quality: recordingQuality, includeAudio: true)) { _ in }
            return true
        } catch {
            try? fileManager.removeItem(at: files.video)
            try? fileManager.moveItem(at: files.screenOriginal, to: files.video)
            message = "Saved the recording without the camera: \(error.localizedDescription)"
            return false
        }
    }

    /// Wire once: if the recorded window closes or the display goes away, save what we have.
    func watchForUnexpectedStop() {
        recorder.onUnexpectedStop = { [weak self] in
            guard let self, self.isRecording else { return }
            self.message = "The recorded window or screen went away, so the recording was stopped and saved."
            Task { await self.stop() }
        }
    }

    func openFolder() {
        let root = LibraryModel.shared.directory
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }
}

struct MenuContent: View {
    @ObservedObject var model: RecorderModel
    @ObservedObject private var library = LibraryModel.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    /// "  (⌃⌥⌘R)" while the shortcut is on, so the menu says what to press.
    private static func hint(_ action: HotkeyAction) -> String {
        guard UserDefaults.standard.object(forKey: Pref.hotkeysEnabled) as? Bool ?? true,
              GlobalHotkeys.shared.problems[action] == nil
        else { return "" }
        let stored = UserDefaults.standard.string(forKey: action.preferenceKey) ?? action.standard.stored
        return HotkeyBinding(stored: stored).map { "  (\($0.display))" } ?? ""
    }

    private func showLibrary() {
        library.refresh()
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "library")
    }

    var body: some View {
        Button {
            model.toggle()
        } label: {
            Label(
                model.isRecording ? "Stop recording" : "New Take",
                systemImage: model.isRecording ? "stop.circle.fill" : "record.circle.fill")
        }
        .keyboardShortcut("n")
        .disabled(model.isBusy)
        if model.isRecording {
            Button("Restart take", systemImage: "arrow.counterclockwise") { model.restart() }
        } else {
            Button("Quick Record" + Self.hint(.startStop), systemImage: "bolt.circle") { model.quickRecord() }
                .disabled(model.isBusy)
                .help("Record the screen you used last right away, with your last settings")
            Button("Quick Take for Agent" + Self.hint(.startAgent), systemImage: "sparkles.rectangle.stack") { model.quickRecordForAgent() }
                .disabled(model.isBusy)
                .help("Like Quick Record, and when you stop, copy the recording as a request for a coding agent. Talk through what you want while you show it.")
            Button("Take Screenshot" + Self.hint(.screenshot), systemImage: "camera.viewfinder") { model.quickScreenshot() }
                .disabled(model.isBusy)
        }
        Button("Speaker Notes", systemImage: "note.text") { SpeakerNotesWindow.shared.toggle() }
            .keyboardShortcut("n", modifiers: [.command, .option])

        switch model.phase {
        case .saving: Text("Saving…")
        case .processing(let text): Text(text)
        case .recording(let since): Text("Recording since \(since.formatted(date: .omitted, time: .shortened))")
        case .idle: EmptyView()
        }
        if !model.message.isEmpty { Text(model.message) }

        Divider()
        Button("Open Hot Takes") { showLibrary() }
            .keyboardShortcut("l")
        if !library.takes.isEmpty {
            Menu("Recent") {
                ForEach(library.takes.prefix(5)) { take in
                    Button(take.title) {
                        library.selection = take.id
                        showLibrary()
                    }
                }
            }
        }
        Divider()
        Button("Open recordings folder") { model.openFolder() }
        Button("Settings…") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openSettings()
        }
        Button("About Hot Take") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "about")
        }
        Button("Quit Hot Take") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

extension Notification.Name {
    static let relaytakeReopen = Notification.Name("relaytake.reopen")
}

/// Keeps the app (and an active recording) alive after the window closes; clicking the app icon
/// brings the main window back.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Double-clicking a `.hottake` file (or dropping one on the icon) adds it to the library.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == HotTakeFile.fileExtension {
            Task { @MainActor in LibraryModel.shared.openPackage(url) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: .relaytakeReopen, object: nil) }
        return false
    }
}

/// Always alive while the app runs, so it can open windows on behalf of the menu.
struct MenuLabel: View {
    @ObservedObject var model: RecorderModel
    @Environment(\.openWindow) private var openWindow

    // A monochrome flame drawn as a template, so the menu bar tints it for light and dark menu bars.
    // The colored app-icon artwork (with its purple background) looked out of place in the menu bar.
    private static let icon: NSImage = {
        let symbol = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "Hot Take")
            ?? NSImage(systemSymbolName: "clapperboard.fill", accessibilityDescription: "Hot Take")!
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            symbol.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: Self.icon)
            if model.isRecording {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
            }
        }
            .accessibilityLabel(model.isRecording ? "Hot Take — recording" : "Hot Take")
            .onChange(of: model.libraryRequest) { _, _ in
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "library")
            }
            .onReceive(NotificationCenter.default.publisher(for: .relaytakeReopen)) { _ in
                openWindow(id: "library")
            }
    }
}

@main
struct RelaytakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = RecorderModel()

    init() {
        // Nothing here has a reason to use the network, so make that a fact: any web request the app
        // or a library makes is refused. (the system's speech models are fetched by the system itself.)
        NetworkGuard.install()
        // `Hot Take --process video.mp4` makes captions, title and summary for an existing video.
        let args = CommandLine.arguments
        // Exercise the same portable format exporter without opening a save panel.
        if let flag = args.firstIndex(of: "--export"), args.count > flag + 3,
           let format = VideoExportFormat(rawValue: args[flag + 3]) {
            Task {
                do {
                    let asset = AVURLAsset(url: URL(fileURLWithPath: args[flag + 1]))
                    let duration = try await asset.load(.duration).seconds
                    let destination = URL(fileURLWithPath: args[flag + 2])
                    guard !FileManager.default.fileExists(atPath: destination.path) else {
                        throw ExportError.failed("Choose a new output filename.")
                    }
                    try await VideoExport.save(asset: asset, segments: [TimeSpan(start: 0, end: duration)],
                        to: destination, format: format, quality: EncodingSettings(preset: .small),
                        includeAudio: !args.contains("--no-audio")) { _ in }
                    print("exported", destination.path); exit(0)
                } catch { print("error:", error.localizedDescription); exit(1) }
            }
        }
        // CLI also provides a repeatable compression check without opening the library.
        if let flag = args.firstIndex(of: "--compress"), args.count > flag + 3,
           let quality = VideoQuality(rawValue: args[flag + 3]) {
            Task {
                do {
                    try await Compressor.save(asset: AVURLAsset(url: URL(fileURLWithPath: args[flag + 1])),
                        to: URL(fileURLWithPath: args[flag + 2]), quality: EncodingPreferences.resolve(quality),
                        includeAudio: !args.contains("--no-audio")) { _ in }
                    print("compressed", args[flag + 2]); exit(0)
                } catch { print("error:", error.localizedDescription); exit(1) }
            }
        }
        // `Hot Take --cut in.mp4 out.mp4 START END` removes START–END seconds (same code as the editor).
        if let flag = args.firstIndex(of: "--cut"), args.count > flag + 4,
           let from = Double(args[flag + 3]), let to = Double(args[flag + 4]) {
            Task {
                do {
                    let asset = AVURLAsset(url: URL(fileURLWithPath: args[flag + 1]))
                    var edit = EditModel(duration: try await asset.load(.duration).seconds)
                    try edit.remove(TimeSpan(start: from, end: to))
                    try await Exporter.save(asset: asset, segments: edit.segments, to: URL(fileURLWithPath: args[flag + 2]),
                        quality: args.count > flag + 5 ? VideoQuality(rawValue: args[flag + 5]).map { EncodingPreferences.resolve($0) } : nil) { _ in }
                    print("saved", args[flag + 2])
                    exit(0)
                } catch { print("error:", error.localizedDescription); exit(1) }
            }
        }
        // `Hot Take --studio-render in out SIZE FORMAT [--no-audio]` and `--studio-save Take.mp4 SIZE [--unedited]`.
        if let flag = args.firstIndex(of: "--studio-render"), args.count > flag + 4 {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                let ok = await StudioChecks.render(
                    video: URL(fileURLWithPath: args[flag + 1]), output: URL(fileURLWithPath: args[flag + 2]),
                    size: args[flag + 3], format: args[flag + 4], noAudio: args.contains("--no-audio"))
                exit(ok ? 0 : 1)
            }
        }
        if let flag = args.firstIndex(of: "--studio-save"), args.count > flag + 2 {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                let ok = await StudioChecks.save(video: URL(fileURLWithPath: args[flag + 1]), size: args[flag + 2], edited: !args.contains("--unedited"))
                exit(ok ? 0 : 1)
            }
        }
        // `Hot Take --network-check` proves the app refuses web requests, then exits 0 (blocked) or 1.
        if args.contains("--network-check") {
            Task { @MainActor in
                do {
                    _ = try await URLSession.shared.data(from: URL(string: "https://example.com/")!)
                    print("FAIL: a web request went out")
                    exit(1)
                } catch let error as URLError where error.code == .notConnectedToInternet {
                    print("ok: web requests are blocked")
                    exit(0)
                } catch {
                    print("FAIL: unexpected error \(error)")
                    exit(1)
                }
            }
        }
        // `Hot Take --playback-check` exercises the pop-out and full-screen windows and prints the results.
        if args.contains("--playback-check") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                exit(await PlaybackCheck.run() ? 0 : 1)
            }
        }
        // `Hot Take --about-snapshot out.png` draws the About window to a PNG.
        if let flag = args.firstIndex(of: "--about-snapshot"), args.count > flag + 1 {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                let host = NSHostingView(rootView: AboutView())
                host.frame = CGRect(origin: .zero, size: host.fittingSize)
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
                host.cacheDisplay(in: host.bounds, to: rep)
                let png = rep.representation(using: .png, properties: [:])
                exit((try? png?.write(to: URL(fileURLWithPath: args[flag + 1]))) != nil ? 0 : 1)
            }
        }
        // `Hot Take --welcome-snapshot out.png [seconds] [--reduce-motion]` draws the first-launch welcome at that moment to a PNG.
        if let flag = args.firstIndex(of: "--welcome-snapshot"), args.count > flag + 1 {
            let seconds = args.count > flag + 2 ? Double(args[flag + 2]) ?? 1.8 : 1.8
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                let host = NSHostingView(rootView: WelcomeScene(elapsed: seconds, animated: !args.contains("--reduce-motion")).frame(width: 1000, height: 680))
                host.frame = CGRect(x: 0, y: 0, width: 1000, height: 680)
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
                host.cacheDisplay(in: host.bounds, to: rep)
                let png = rep.representation(using: .png, properties: [:])
                exit((try? png?.write(to: URL(fileURLWithPath: args[flag + 1]))) != nil ? 0 : 1)
            }
        }
        // `Hot Take --settings-snapshot out.png` draws the Settings window to a PNG.
        if let flag = args.firstIndex(of: "--settings-snapshot"), args.count > flag + 1 {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                let host = NSHostingView(rootView: SettingsView().environment(\.colorScheme, .dark))
                host.frame = CGRect(origin: .zero, size: host.fittingSize)
                host.appearance = NSAppearance(named: .darkAqua)
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
                host.cacheDisplay(in: host.bounds, to: rep)
                let png = rep.representation(using: .png, properties: [:])
                exit((try? png?.write(to: URL(fileURLWithPath: args[flag + 1]))) != nil ? 0 : 1)
            }
        }
        // `Hot Take --record-sheet-snapshot out.png` draws the record sheet (Area mode, so no screen contents) to a PNG,
        // with its settings in a scratch defaults suite so the real ones are untouched.
        if let flag = args.firstIndex(of: "--record-sheet-snapshot"), args.count > flag + 1 {
            Task { @MainActor in
                let defaults = UserDefaults(suiteName: "org.relaytake.snapshot")!
                defaults.removePersistentDomain(forName: "org.relaytake.snapshot")
                let host = NSHostingView(rootView: SourceChooser(recorder: RecorderModel(), mode: "area").defaultAppStorage(defaults))
                host.frame = CGRect(origin: .zero, size: host.fittingSize)
                try? await Task.sleep(for: .seconds(1))
                host.frame = CGRect(origin: .zero, size: host.fittingSize)
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
                host.cacheDisplay(in: host.bounds, to: rep)
                let png = rep.representation(using: .png, properties: [:])
                exit((try? png?.write(to: URL(fileURLWithPath: args[flag + 1]))) != nil ? 0 : 1)
            }
        }
        // `Hot Take --record-check dir seconds` makes one real recording (with the chosen camera, if any) into `dir`, saves
        // it the way Stop does, and writes dir/report.txt. It uses the screen of the main display.
        if let flag = args.firstIndex(of: "--record-check"), args.count > flag + 2 {
            Task { @MainActor in
                let dir = URL(fileURLWithPath: args[flag + 1])
                let seconds = Double(args[flag + 2]) ?? 6
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                var report = ""
                func note(_ line: String) { report += "[\(String(format: "%5.1f", Date().timeIntervalSince(began))) s] \(line)\n" }
                let began = Date()
                let model = RecorderModel()
                model.directoryOverride = dir
                if let id = NSScreen.main?.displayID { model.begin(.screen(id)) }
                var waited = 0.0
                while !model.isRecording, waited < 30 { try? await Task.sleep(for: .milliseconds(100)); waited += 0.1 }
                note("recording: \(model.isRecording); message: \(model.message)")
                if args.contains("--pause") {
                    try? await Task.sleep(for: .seconds(seconds / 2))
                    model.pause()
                    note("paused")
                    try? await Task.sleep(for: .seconds(2))
                    let resumed = Date()
                    model.resume()
                    var waitedForResume = 0.0
                    while model.paused, waitedForResume < 20 { try? await Task.sleep(for: .milliseconds(50)); waitedForResume += 0.05 }
                    note("resumed after \(String(format: "%.2f", Date().timeIntervalSince(resumed))) s; message: \(model.message)")
                    try? await Task.sleep(for: .seconds(seconds / 2))
                } else {
                    try? await Task.sleep(for: .seconds(seconds))
                }
                note("pressing stop")
                model.toggle()
                try? await Task.sleep(for: .seconds(1))
                waited = 0
                while model.phase != .idle, waited < 120 { try? await Task.sleep(for: .milliseconds(200)); waited += 0.2 }
                note("finished saving; message: \(model.message)")
                let files = ((try? FileManager.default.subpathsOfDirectory(atPath: dir.path)) ?? []).sorted()
                for name in files where !name.hasSuffix("report.txt") {
                    let size = (try? dir.appendingPathComponent(name).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    note("file \(name): \(size) bytes")
                }
                if let json = files.first(where: { $0.hasSuffix(".json") }), let text = try? String(contentsOf: dir.appendingPathComponent(json), encoding: .utf8) {
                    for key in ["cameraOffset", "cameraPlacement"] where text.contains(key) { note("metadata has \(key)") }
                }
                try? report.write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
                exit(0)
            }
        }
        // `Hot Take --camera-check out.mov` records 3 seconds from the chosen camera and writes a report to out.mov.txt.
        if let flag = args.firstIndex(of: "--camera-check"), args.count > flag + 1 {
            Task { @MainActor in
                let out = URL(fileURLWithPath: args[flag + 1])
                var report = ""
                func note(_ line: String) { report += line + "\n" }
                let camera = CameraSession()
                await camera.requestAccess()
                note("authorized: \(camera.isAuthorized)")
                let chosen = UserDefaults.standard.string(forKey: Pref.cameraDevice) ?? ""
                let id = CameraChoice.available().contains { $0.id == chosen } ? chosen : (CameraChoice.available().first?.id ?? "")
                note("camera: \(id.isEmpty ? "none" : "found")")
                let configured = await camera.configure(cameraID: id)
                note("configured: \(configured)")
                if configured {
                    camera.startPreview()
                    if args.contains("--like-the-sheet") {
                        // What closing the record sheet used to do: switch the camera off just after it was switched on.
                        try? await Task.sleep(for: .milliseconds(300))
                        camera.stopPreview()
                        try? await Task.sleep(for: .seconds(3))
                        camera.startPreview()
                        note("replayed the sheet closing, then a 3 s countdown")
                    }
                    if args.contains("--self-view"), let area = NSScreen.main?.frame {
                        SelfViewPanel.shared.show(camera: camera, over: area, placement: nil, size: 0.24)
                        note("self view shown before recording")
                    }
                    let asked = Date()
                    let began = await camera.record(to: out)
                    note("started: \(began != nil) after \(Date().timeIntervalSince(asked)) s; problem: \(camera.problem)")
                    try? await Task.sleep(for: .seconds(3))
                    let asked2 = Date()
                    let finished = await camera.finish()
                    note("finished: \(finished) after \(Date().timeIntervalSince(asked2)) s; problem: \(camera.problem)")
                    let asset = AVURLAsset(url: out)
                    let seconds = (try? await asset.load(.duration).seconds) ?? -1
                    let tracks = (try? await asset.loadTracks(withMediaType: .video).count) ?? -1
                    let size = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                    note("file: \(size) bytes, \(seconds) s, video tracks \(tracks)")
                }
                try? report.write(to: URL(fileURLWithPath: out.path + ".txt"), atomically: true, encoding: .utf8)
                exit(0)
            }
        }
        // `Hot Take --join-check out.mp4 a.mp4 b.mp4` joins pieces the way a paused take is joined, and prints the length.
        if let flag = args.firstIndex(of: "--join-check"), args.count > flag + 3 {
            Task { @MainActor in
                let pieces = args[(flag + 2)...].map { URL(fileURLWithPath: $0) }
                do {
                    try await SegmentJoiner.join(Array(pieces), to: URL(fileURLWithPath: args[flag + 1]), as: .mp4)
                    let joined = AVURLAsset(url: URL(fileURLWithPath: args[flag + 1]))
                    print("joined \(try await joined.load(.duration).seconds) s, video tracks \(try await joined.loadTracks(withMediaType: .video).count)")
                    exit(0)
                } catch {
                    print("join failed: \(error)")
                    exit(1)
                }
            }
        }
        // `Hot Take --trim-check out.mp4 in.mp4 SECONDS` copies a piece and cuts it short, the way a rewind does, and prints the length.
        if let flag = args.firstIndex(of: "--trim-check"), args.count > flag + 3, let seconds = Double(args[flag + 3]) {
            Task { @MainActor in
                let out = URL(fileURLWithPath: args[flag + 1])
                do {
                    try? FileManager.default.removeItem(at: out)
                    try FileManager.default.copyItem(at: URL(fileURLWithPath: args[flag + 2]), to: out)
                    try await SegmentJoiner.trim(out, to: seconds, as: .mp4)
                    let asset = AVURLAsset(url: out)
                    print("trimmed to \(try await asset.load(.duration).seconds) s, video tracks \(try await asset.loadTracks(withMediaType: .video).count), audio tracks \(try await asset.loadTracks(withMediaType: .audio).count)")
                    exit(0)
                } catch {
                    print("trim failed: \(error)")
                    exit(1)
                }
            }
        }
        // `Hot Take --splice-check Take.mp4` splices, slides, trims and undoes through the Studio's own model.
        if let flag = args.firstIndex(of: "--splice-check"), args.count > flag + 1 {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                exit(await SpliceCheck.run(video: URL(fileURLWithPath: args[flag + 1])) ? 0 : 1)
            }
        }
        // `Hot Take --studio-snapshot Take.mp4 song.m4a out.png [width height]` draws the Studio to a PNG.
        if let flag = args.firstIndex(of: "--studio-snapshot"), args.count > flag + 3 {
            let width = args.count > flag + 4 ? Double(args[flag + 4]) ?? 1000 : 1000
            let height = args.count > flag + 5 ? Double(args[flag + 5]) ?? 700 : 700
            let variant = args.count > flag + 6 ? args[flag + 6] : "studio"
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                let music = args[flag + 2] == "-" ? nil : URL(fileURLWithPath: args[flag + 2])
                let ok = await StudioSnapshot.run(
                    video: URL(fileURLWithPath: args[flag + 1]), music: music, output: URL(fileURLWithPath: args[flag + 3]),
                    width: width, height: height, variant: variant)
                print(ok ? "snapshot saved" : "snapshot failed")
                exit(ok ? 0 : 1)
            }
        }
        // `Hot Take --fields video.mp4` prints the title, summary, tags and notes the model writes.
        if let flag = args.firstIndex(of: "--fields"), args.indices.contains(flag + 1) {
            let url = URL(fileURLWithPath: args[flag + 1])
            Task {
                let dir = url.deletingLastPathComponent()
                let name = url.deletingPathExtension().lastPathComponent
                guard let entry = TakeLibrary.load(directory: dir).first(where: { $0.files.baseName == name }) else { print("not found"); exit(1) }
                do {
                    let segments = try await Transcripts.ensure(for: entry)
                    let transcript = Captions.plainText(segments)
                    for field in MetadataField.allCases {
                        print("--- \(field.label)\n\(try await Summarizer.generate(field, transcript: transcript))")
                    }
                    exit(0)
                } catch { print("error:", error.localizedDescription); exit(1) }
            }
        }
        // `Hot Take --suggest video.mp4` prints quiet parts and recommended cuts (nothing is changed).
        if let flag = args.firstIndex(of: "--suggest"), args.indices.contains(flag + 1) {
            let url = URL(fileURLWithPath: args[flag + 1])
            Task {
                let dir = url.deletingLastPathComponent()
                let files = TakeFiles(directory: dir, baseName: url.deletingPathExtension().lastPathComponent)
                let entry = TakeLibrary.load(directory: dir).first { $0.files.baseName == files.baseName }
                guard let entry else { print("not found in folder"); exit(1) }
                let result = await EditAnalysis.run(for: entry) { print($0) }
                if let t = result.noiseThreshold { print(String(format: "threshold %.1f dB", t)) }
                for s in result.suggestions {
                    print(String(format: "%@ %.2f–%.2f (%.1f s) %@", s.kind.rawValue, s.span.start, s.span.end, s.span.length, s.reason))
                }
                result.notes.forEach { print("note:", $0) }
                exit(0)
            }
        }
        // `Hot Take --chapters video.mp4` prints suggested chapters (nothing is saved).
        if let flag = args.firstIndex(of: "--chapters"), args.indices.contains(flag + 1) {
            let url = URL(fileURLWithPath: args[flag + 1])
            Task {
                let dir = url.deletingLastPathComponent()
                let name = url.deletingPathExtension().lastPathComponent
                guard let entry = TakeLibrary.load(directory: dir).first(where: { $0.files.baseName == name }) else {
                    print("not found in folder")
                    exit(1)
                }
                let result = await ChapterAnalysis.run(for: entry) { print($0) }
                print(ChapterList.timestampList(result.chapters))
                result.notes.forEach { print("note:", $0) }
                exit(0)
            }
        }
        if let flag = args.firstIndex(of: "--process"), args.indices.contains(flag + 1) {
            let url = URL(fileURLWithPath: args[flag + 1])
            Task {
                let take = TakeFiles(
                    directory: url.deletingLastPathComponent(),
                    baseName: url.deletingPathExtension().lastPathComponent)
                let notes = await Pipeline.process(
                    take: take, created: Date(), options: .init(captions: true, summary: !args.contains("--captions-only"))
                ) { print($0) }
                notes.forEach { print("note:", $0) }
                if let data = try? Data(contentsOf: take.metadata) { print(String(decoding: data, as: UTF8.self)) }
                exit(notes.isEmpty ? 0 : 1)
            }
        }
    }

    var body: some Scene {
        // The library is the main window; it opens at launch.
        Window("Hot Take", id: "library") {
            LibraryView(library: LibraryModel.shared, recorder: model)
        }
        .defaultSize(width: 1000, height: 680)

        // Quick start/stop while the main window is hidden (it hides itself during recording).
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuLabel(model: model)
        }

        // A real Settings scene: gets the standard ⌘, shortcut and the system's tabbed Settings window.
        Settings {
            SettingsView()
        }

        Window("About Hot Take", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("What's New", id: "whats-new") {
            WhatsNewView()
        }

        Window("Hot Take Help", id: "help") {
            HelpView()
        }
        .commands {
            AboutCommands(); HelpCommands(); TranscriptFindCommands()
            FileCommands(recorder: model); RecordCommands(recorder: model); TakeCommands(recorder: model)
            StudioCommands(); ViewCommands()
        }
    }
}
