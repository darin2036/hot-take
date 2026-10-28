import AVFoundation
import Foundation

/// A microphone that can be chosen for a voiceover.
struct Microphone: Identifiable, Hashable {
    let id: String  // the device's unique ID; "" means the system's default input
    let name: String

    /// Every audio input the Mac currently has, with the default first.
    static func available() -> [Microphone] {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
        let defaultName = AVCaptureDevice.default(for: .audio)?.localizedName
        let first = Microphone(id: "", name: defaultName.map { "Default (\($0))" } ?? "Default")
        return [first] + devices.map { Microphone(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// The saved choice, falling back to the default when that microphone is no longer connected.
    static func chosen(id: String) -> (device: AVCaptureDevice?, fellBack: Bool) {
        guard !id.isEmpty else { return (AVCaptureDevice.default(for: .audio), false) }
        if let device = AVCaptureDevice(uniqueID: id) { return (device, false) }
        return (AVCaptureDevice.default(for: .audio), true)
    }
}

/// How the system is processing this app's microphone. The person chooses it in the system's own Mic Modes
/// menu; an app can read the choice and open the menu, but cannot change it.
enum MicrophoneModeStatus: Equatable {
    case standard, voiceIsolation, wideSpectrum

    init(_ mode: AVCaptureDevice.MicrophoneMode) {
        switch mode {
        case .voiceIsolation: self = .voiceIsolation
        case .wideSpectrum: self = .wideSpectrum
        default: self = .standard
        }
    }

    /// The mode chosen in Control Center for this app.
    static func current() -> MicrophoneModeStatus { MicrophoneModeStatus(AVCaptureDevice.preferredMicrophoneMode) }

    /// The mode macOS is really applying. It only means something while this app has a microphone open, and it can
    /// differ from the chosen one (some microphones cannot do Voice Isolation).
    static func active() -> MicrophoneModeStatus { MicrophoneModeStatus(AVCaptureDevice.activeMicrophoneMode) }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .voiceIsolation: "Voice Isolation"
        case .wideSpectrum: "Wide Spectrum"
        }
    }

    /// One line for the record sheet: what the current mode does, and what to try if it is not Voice Isolation.
    var hint: String {
        switch self {
        case .voiceIsolation: "Background noise is filtered out so your voice comes through."
        case .standard: "Choose Voice Isolation to filter out background noise."
        case .wideSpectrum: "Records the whole room. Choose Voice Isolation for just your voice."
        }
    }

    static func openSystemMenu() { AVCaptureDevice.showSystemUserInterface(.microphoneModes) }
}

/// Records one microphone to an M4A file. Unlike AVAudioRecorder, which always uses the system's default
/// input, this records from whichever input is chosen.
final class MicrophoneRecorder: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioFileOutput()
    private var finished: CheckedContinuation<URL?, Never>?
    let url: URL

    init(url: URL) { self.url = url }

    /// Starts recording. Throws if the microphone cannot be opened.
    func start(device: AVCaptureDevice?) throws {
        guard let device else { throw MicrophoneError.noMicrophone }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw MicrophoneError.unavailable(device.localizedName)
        }
        session.addInput(input)
        session.addOutput(output)
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000,
        ]
        session.commitConfiguration()
        session.startRunning()
        try? FileManager.default.removeItem(at: url)
        output.startRecording(to: url, outputFileType: .m4a, recordingDelegate: self)
    }

    /// Input loudness from 0 to 1, for a level meter.
    var level: Double {
        guard let power = output.connections.first?.audioChannels.first?.averagePowerLevel, power.isFinite else { return 0 }
        return min(1, max(0, (Double(power) + 55) / 55))
    }

    /// Stops and waits until the file is complete. Returns nil if nothing was recorded.
    func stop() async -> URL? {
        guard output.isRecording else {
            session.stopRunning()
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return await withCheckedContinuation { continuation in
            finished = continuation
            output.stopRecording()
        }
    }

    func discard() {
        if output.isRecording { output.stopRecording() }
        session.stopRunning()
        try? FileManager.default.removeItem(at: url)
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        session.stopRunning()
        // AVFoundation reports an error alongside a usable file when recording simply ended; trust the file.
        let usable = FileManager.default.fileExists(atPath: outputFileURL.path)
        finished?.resume(returning: usable ? outputFileURL : nil)
        finished = nil
    }
}

enum MicrophoneError: LocalizedError {
    case noMicrophone
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .noMicrophone: "No microphone was found. Connect one, or check System Settings → Sound → Input."
        case .unavailable(let name): "“\(name)” could not be opened. Try another microphone."
        }
    }
}
