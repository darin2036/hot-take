@preconcurrency import AVFoundation
import AppKit
import RelaytakeCore
import SwiftUI

/// The cameras that can be chosen in the record sheet.
struct CameraChoice: Identifiable, Hashable {
    let id: String
    let name: String

    static func available() -> [CameraChoice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video, position: .unspecified)
        return session.devices.map { CameraChoice(id: $0.uniqueID, name: $0.localizedName) }
    }
}

/// What the system's video effects are doing right now. These are chosen in the system's own Video Effects
/// panel and apply to this app while the camera is on.
struct CameraEffectsStatus: Equatable {
    var centerStage = false
    var backgroundBlur = false
    var studioLight = false
    var reactions = false

    static func current() -> CameraEffectsStatus {
        CameraEffectsStatus(
            centerStage: AVCaptureDevice.isCenterStageEnabled,
            backgroundBlur: AVCaptureDevice.isPortraitEffectEnabled,
            studioLight: AVCaptureDevice.isStudioLightEnabled,
            reactions: AVCaptureDevice.reactionEffectGesturesEnabled)
    }

    var summary: [String] {
        var names: [String] = []
        if centerStage { names.append("Center Stage") }
        if backgroundBlur { names.append("Background blur") }
        if studioLight { names.append("Studio Light") }
        if reactions { names.append("Reactions") }
        return names
    }
}

/// Every call that starts, stops or reconfigures a capture session, including attaching or detaching a preview layer,
/// waits on the session's lock for as long as the session is starting or stopping. They all run here, one at a time,
/// so the main thread never waits on that lock.
let cameraSessionQueue = DispatchQueue(label: "org.relaytake.camera-session")

/// Opens a camera on its own session, either to show a live preview or to record to a file.
/// The preview in the record sheet and the recording never run at once: the sheet closes before recording starts.
@MainActor
final class CameraSession: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let movie = AVCaptureMovieFileOutput()
    /// Starting and stopping a session can take a while, so it happens here, one change at a time, never on the main thread.
    private var sessionQueue: DispatchQueue { cameraSessionQueue }
    private var configuredID: String?
    private var isRecording = false
    /// Identifies the latest start or finish request, so a timeout from an earlier one cannot cut a later one short.
    private var startToken = UUID()
    private var finishToken = UUID()
    private var started: CheckedContinuation<Date?, Never>?
    private var finished: CheckedContinuation<Bool, Never>?
    @Published private(set) var status: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var problem = ""

    var isAuthorized: Bool { status == .authorized }

    /// Asks the system the first time. The camera is never touched without the person choosing one.
    func requestAccess() async {
        if status == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video) }
        status = AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Points the session at a camera. Returns false when it cannot be opened. The session is only ever touched on its own
    /// queue: reading or changing it from the main thread can wait on the queue that is starting or stopping it.
    func configure(cameraID: String) async -> Bool {
        guard status == .authorized else { return false }
        if configuredID == cameraID { return true }
        let session = session, movie = movie
        let ok: Bool = await withCheckedContinuation { continuation in
            sessionQueue.async {
                guard let device = AVCaptureDevice(uniqueID: cameraID), let input = try? AVCaptureDeviceInput(device: device) else {
                    continuation.resume(returning: false)
                    return
                }
                session.beginConfiguration()
                session.inputs.forEach { session.removeInput($0) }
                if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
                if session.canAddInput(input) { session.addInput(input) }
                if !session.outputs.contains(movie), session.canAddOutput(movie) { session.addOutput(movie) }
                session.commitConfiguration()
                continuation.resume(returning: !session.inputs.isEmpty)
            }
        }
        configuredID = ok ? cameraID : nil
        problem = ok ? "" : "That camera is not available."
        return ok
    }

    func startPreview() {
        let session = session
        sessionQueue.async { if !session.isRunning { session.startRunning() } }
    }

    func stopPreview() {
        guard !isRecording else { return }
        let session = session
        sessionQueue.async { if session.isRunning { session.stopRunning() } }
    }

    /// Starts recording to `url`. Returns when the first frame is being written, with that moment, or nil on failure.
    func record(to url: URL) async -> Date? {
        guard configuredID != nil else { return nil }
        startPreview()
        // Wait (off the main thread) until the session is delivering frames before asking it to record. Restarting
        // after a pause can take a moment, so this waits longer than a fresh start.
        let session = session
        let running: Bool = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            sessionQueue.async {
                for _ in 0..<120 where !session.isRunning { Thread.sleep(forTimeInterval: 0.05) }
                done.resume(returning: session.isRunning)
            }
        }
        guard running else {
            problem = "The camera session did not start."
            return nil
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        problem = ""
        let date: Date? = await withCheckedContinuation { continuation in
            let token = UUID()
            startToken = token
            started = continuation
            isRecording = true
            let movie = movie
            sessionQueue.async { movie.startRecording(to: url, recordingDelegate: self) }
            // A camera that never reports starting should not hold the recording back.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                if startToken == token, let pending = started {
                    started = nil
                    problem = "The camera did not report starting."
                    pending.resume(returning: nil)
                }
            }
        }
        if date == nil { isRecording = false }
        return date
    }

    /// Stops and waits for the file to be finished. True when a usable file was written.
    /// With `keepRunning`, the camera stays on afterwards (for a short pause), so recording again is instant.
    func finish(keepRunning: Bool = false) async -> Bool {
        guard isRecording else { if !keepRunning { stopPreview() }; return false }
        let movie = movie
        let ok = await withCheckedContinuation { continuation in
            let token = UUID()
            finishToken = token
            finished = continuation
            // Not queued: the camera queue may be busy with the self view coming off the session, and stopping must not wait for that.
            movie.stopRecording()
            // Never hold up a stop or restart for long: if the system does not report the file, carry on without the camera.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                if self.finishToken == token, let pending = self.finished {
                    self.finished = nil
                    self.problem = "The camera did not finish its file in time."
                    pending.resume(returning: false)
                }
            }
        }
        isRecording = false
        if !keepRunning { stopPreview() }
        return ok
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        let now = Date()
        Task { @MainActor in
            if let pending = self.started { self.started = nil; pending.resume(returning: now) }
        }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: (any Error)?) {
        // The system reports an error for some benign endings (a full disk, for instance, still leaves a file).
        let usable = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
        let reason = error?.localizedDescription ?? ""
        Task { @MainActor in
            // A recording that fails before it starts ends here instead, so report why.
            if let pending = self.started {
                self.started = nil
                self.problem = reason.isEmpty ? "The camera stopped before it started." : reason
                pending.resume(returning: nil)
            }
            if !usable, !reason.isEmpty { self.problem = reason }
            if let pending = self.finished { self.finished = nil; pending.resume(returning: usable) }
        }
    }
}

/// A live camera picture, mirrored like a mirror.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    /// Dragging the picture moves the window it is in (used by the floating self view).
    var draggable = false

    func makeNSView(context: Context) -> PreviewHost {
        let host = PreviewHost()
        host.draggable = draggable
        host.previewLayer.videoGravity = .resizeAspectFill
        nonisolated(unsafe) let layer = host.previewLayer
        nonisolated(unsafe) let session = session
        cameraSessionQueue.async { layer.session = session }
        return host
    }

    func updateNSView(_ host: PreviewHost, context: Context) { host.draggable = draggable }

    /// The layer is let go on the session queue: releasing it from the main thread waits on the session's lock.
    static func dismantleNSView(_ host: PreviewHost, coordinator: ()) {
        nonisolated(unsafe) let layer = host.previewLayer
        host.layer = nil
        cameraSessionQueue.async { layer.session = nil }
    }

    final class PreviewHost: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        var draggable = false
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = previewLayer
        }
        required init?(coder: NSCoder) { fatalError("not used") }

        // The picture takes the click, so a window-background drag never starts; start the window drag here instead.
        override var mouseDownCanMoveWindow: Bool { draggable }
        override func mouseDown(with event: NSEvent) {
            if draggable { window?.performDrag(with: event) } else { super.mouseDown(with: event) }
        }
    }
}
