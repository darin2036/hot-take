import AVFoundation
import Foundation
import os
import OSLog

/// Keeps the chosen microphone open, recording nothing, while the record sheet or Settings is showing. macOS only
/// offers its Mic Modes menu (Standard, Voice Isolation, Wide Spectrum) for an app that is using the microphone, the
/// way the camera has to be on for Video Effects. The sound is thrown away; nothing is saved or sent anywhere.
/// It steps aside whenever a recording or save is under way, so it never competes with the real capture.
@MainActor
final class MicrophoneMonitor: ObservableObject {
    static let shared = MicrophoneMonitor()

    @Published private(set) var access = AVCaptureDevice.authorizationStatus(for: .audio)
    /// The mode chosen in Control Center.
    @Published private(set) var preferred = MicrophoneModeStatus.current()
    /// The mode macOS is applying right now; nil while the microphone is not open here.
    @Published private(set) var active: MicrophoneModeStatus?

    private let engine = Engine()
    private var holders: Set<String> = []
    private var deviceID = ""
    private var poll: Task<Void, Never>?
    private let log = Logger(subsystem: "org.relaytake.mac", category: "microphone")

    var isAuthorized: Bool { access == .authorized }

    /// Asks the system the first time.
    func requestAccess() async {
        if access == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .audio) }
        access = AVCaptureDevice.authorizationStatus(for: .audio)
        update()
    }

    /// `owner` is whoever needs the microphone open (a window); it stays open until every owner has let go.
    func hold(_ owner: String, deviceID: String) {
        holders.insert(owner)
        self.deviceID = deviceID
        access = AVCaptureDevice.authorizationStatus(for: .audio)
        if poll == nil {
            poll = Task { [weak self] in
                // The mode can be changed in Control Center while a window is open, so read it again.
                while !Task.isCancelled {
                    self?.update()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
        update()
    }

    /// Opens the system's Mic Modes menu. The menu only appears while this app has the microphone open, so this makes
    /// sure it is, and waits for it to be running, before asking. (Asking with no microphone open does nothing.)
    func openSystemMenu(owner: String, deviceID: String) async {
        hold(owner, deviceID: deviceID)
        for _ in 0..<80 where !engine.isRunning { try? await Task.sleep(for: .milliseconds(50)) }
        update()
        let busy = RecorderModel.current.map { $0.phase != .idle } ?? false
        log.info("Mic Modes menu requested: microphone open \(self.engine.isRunning, privacy: .public), allowed \(self.isAuthorized, privacy: .public), recording or saving \(busy, privacy: .public)")
        MicrophoneModeStatus.openSystemMenu()
    }

    func release(_ owner: String) {
        holders.remove(owner)
        if holders.isEmpty {
            poll?.cancel()
            poll = nil
        }
        update()
    }

    private func update() {
        preferred = MicrophoneModeStatus.current()
        let busy = RecorderModel.current.map { $0.phase != .idle } ?? false
        if holders.isEmpty || busy || !isAuthorized {
            engine.stop()
            active = nil
        } else {
            engine.start(deviceID: deviceID)
            active = engine.isRunning ? MicrophoneModeStatus.active() : nil
        }
    }
}

/// The capture session behind the monitor. Starting and stopping can take a while, so it all happens on its own queue.
private final class Engine: @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let sink = Discard()
    private let queue = DispatchQueue(label: "org.relaytake.microphone-monitor")
    private var configured: String?
    private let running = OSAllocatedUnfairLock(initialState: false)

    var isRunning: Bool { running.withLock { $0 } }

    func start(deviceID: String) {
        queue.async { [self] in
            guard let device = Microphone.chosen(id: deviceID).device else { return }
            if configured != device.uniqueID || session.inputs.isEmpty {
                session.beginConfiguration()
                session.inputs.forEach { session.removeInput($0) }
                configured = nil
                if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                    session.addInput(input)
                    configured = device.uniqueID
                }
                if !session.outputs.contains(output), session.canAddOutput(output) {
                    output.setSampleBufferDelegate(sink, queue: queue)
                    session.addOutput(output)
                }
                session.commitConfiguration()
            }
            if !session.isRunning, !session.inputs.isEmpty { session.startRunning() }
            running.withLock { $0 = session.isRunning }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            running.withLock { $0 = false }
        }
    }

    /// The sound is not used; the session only has to be open.
    private final class Discard: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {}
    }
}
