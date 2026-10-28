import AVFoundation
import Foundation
import RelaytakeCore
import OSLog
import ScreenCaptureKit

enum RecorderError: LocalizedError {
    case noDisplay
    case notRecording
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay: "No display found to record."
        case .notRecording: "Nothing is being recorded."
        case .failed(let message): message
        }
    }
}

/// What to record. A window or app comes from the system content picker.
enum RecordingTarget {
    case display(CGDirectDisplayID)
    case window(SCContentFilter)
    /// `rect` is in points, relative to the display's top-left corner.
    case region(display: CGDirectDisplayID, rect: CGRect)
}

/// Records a screen, window, app or area to an MP4 using ScreenCaptureKit's built-in file writer, so the file
/// has correct duration and seeking. Pause is not supported by SCRecordingOutput.
@MainActor
final class ScreenRecorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var finished: CheckedContinuation<Void, Never>?
    private var failure: String?
    private(set) var startedAt: Date?
    private var outputURL: URL?
    private let log = Logger(subsystem: "org.relaytake.mac", category: "save")

    var isRecording: Bool { stream != nil }

    /// Called when capture ends by itself (window closed, display unplugged), not via `stop()`.
    var onUnexpectedStop: (() -> Void)?
    private var streamEnded = false

    func start(to url: URL, target: RecordingTarget, microphone: Bool, microphoneID: String = "", systemAudio: Bool, includeOwnWindows: Bool = false, hideNotifications: Bool = true, quality: EncodingSettings = EncodingSettings(preset: .medium)) async throws {
        // First call triggers the system's Screen Recording permission prompt.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        // Keep Hot Take's own windows (library, control bar) out of the video, unless the user is recording
        // the app itself. Then its normal windows stay in (those open now); the floating control bar and
        // countdown still do not appear.
        // Notification Center is left out too when asked, so a banner that pops up is not in the video. (Whether
        // banners are really its windows has to be checked on a Mac; see the README.)
        let leftOut = Set(CaptureExclusions.bundleIdentifiers(
            ownApp: Bundle.main.bundleIdentifier, includeOwnApp: false, hideNotifications: hideNotifications))
        let ours = content.applications.filter { leftOut.contains($0.bundleIdentifier) }
        let keptWindows = includeOwnWindows
            ? content.windows.filter { $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier && $0.windowLayer == 0 }
            : []

        func display(_ id: CGDirectDisplayID) throws -> SCDisplay {
            guard let found = content.displays.first(where: { $0.displayID == id })
            else { throw RecorderError.noDisplay }
            return found
        }

        let filter: SCContentFilter
        var sourceRect: CGRect?
        switch target {
        case .display(let id):
            filter = SCContentFilter(display: try display(id), excludingApplications: ours, exceptingWindows: keptWindows)
        case .region(let id, let rect):
            filter = SCContentFilter(display: try display(id), excludingApplications: ours, exceptingWindows: keptWindows)
            sourceRect = rect
        case .window(let selected):
            filter = selected
        }

        let scale = CGFloat(filter.pointPixelScale)
        let size = sourceRect?.size ?? filter.contentRect.size
        let configuration = SCStreamConfiguration()
        let pixels = CaptureGeometry.evenPixelSize(points: size, scale: scale)
        let fitted = quality.dimensions(width: Double(pixels.width), height: Double(pixels.height))
        configuration.width = fitted.width
        configuration.height = fitted.height
        if let sourceRect { configuration.sourceRect = sourceRect }
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(quality.fps))
        configuration.showsCursor = true
        configuration.sampleRate = 48_000
        configuration.channelCount = quality.channels
        // A window recording is just the window: no drop shadow around it, so a backdrop can be added later.
        if case .window = target { configuration.ignoreShadowsSingleWindow = true }
        configuration.capturesAudio = systemAudio
        configuration.captureMicrophone = microphone
        // A microphone that has been unplugged since it was chosen falls back to the system default.
        if microphone, !microphoneID.isEmpty, AVCaptureDevice(uniqueID: microphoneID) != nil {
            configuration.microphoneCaptureDeviceID = microphoneID
        }

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = url
        recordingConfiguration.outputFileType = .mp4
        recordingConfiguration.videoCodecType = .h264

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let output = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        try stream.addRecordingOutput(output)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await stream.startCapture()

        self.stream = stream
        self.output = output
        failure = nil
        streamEnded = false
        outputURL = url
        startedAt = Date()
    }

    /// Stops capture and waits until the MP4 is finalized on disk.
    func stop() async throws -> TimeInterval {
        guard let stream else { throw RecorderError.notRecording }
        let duration = Date().timeIntervalSince(startedAt ?? Date())
        let began = Date()
        let url = outputURL
        await withCheckedContinuation { continuation in
            finished = continuation
            Task {
                if !self.streamEnded {
                    do { try await stream.stopCapture() } catch { self.failure = error.localizedDescription }
                }
                // The writer normally reports when it is done, which resumes this wait. Do not rely on that alone: the
                // file is finished as soon as it can be read, so check for that too, and give up only after a while.
                let limit = Date().addingTimeInterval(self.streamEnded ? 3 : 10)
                while self.finished != nil, Date() < limit {
                    if let url, await Self.isReadable(url) { break }
                    try? await Task.sleep(for: .milliseconds(150))
                }
                self.resumeFinished()
            }
        }
        log.info("screen file closed \(Date().timeIntervalSince(began), format: .fixed(precision: 2)) s after stop")
        self.stream = nil
        output = nil
        startedAt = nil
        if let failure { throw RecorderError.failed(failure) }
        return duration
    }

    /// A recording is only readable once its writer has finished it.
    private static func isReadable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isNumeric, duration.seconds > 0 else { return false }
        return (try? await asset.load(.isReadable)) ?? false
    }

    private func resumeFinished() {
        finished?.resume()
        finished = nil
    }

    // MARK: SCRecordingOutputDelegate

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.resumeFinished() }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in
            self.failure = error.localizedDescription
            self.resumeFinished()
        }
    }

    // MARK: SCStreamDelegate

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let ended = ObjectIdentifier(stream)
        Task { @MainActor in
            // An error from a take that already ended (a restart stops one and starts the next) must not stop the new take.
            guard self.stream.map(ObjectIdentifier.init) == ended else { return }
            self.streamEnded = true
            if self.finished == nil {
                // Capture ended on its own; let the owner save what was recorded.
                self.onUnexpectedStop?()
            } else {
                self.failure = error.localizedDescription
                self.resumeFinished()
            }
        }
    }
}
