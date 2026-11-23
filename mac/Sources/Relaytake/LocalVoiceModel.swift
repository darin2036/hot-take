import AVFoundation
import Foundation
import KokoroSwift
import MLX
import PlainspokenSpeech
import RelaytakeCore
import SwiftUI

// The voice that runs on this Mac: Kokoro, an open-weight model (Apache-2.0), run with Apple's MLX on the GPU. Speaking a line sends
// nothing anywhere. The model and ten voices are one download the person approves in Settings ▸ Voice, from Hugging Face, and each file
// is checked against a fixed SHA-256 before it is kept, so a changed or damaged file is never used.

/// Where the download is, what it holds, and the buttons that start, stop and remove it.
@MainActor
final class LocalVoiceStore: ObservableObject {
    static let shared = LocalVoiceStore()

    enum State: Equatable {
        case notInstalled
        case downloading(bytes: Int, of: Int)
        case ready
        case failed(String)
    }

    @Published private(set) var state: State

    /// `~/Library/Application Support/Hot Take/Kokoro`. Everything in it is made by this app and is safe to remove.
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Hot Take/Kokoro", isDirectory: true)
    }

    private var task: Task<Void, Never>?

    private init() { state = Self.installedState() }

    private static func installedState() -> State { KokoroModel.missing(in: folder).isEmpty ? .ready : .notInstalled }

    var isReady: Bool { state == .ready }

    var voice: KokoroModel.Voice {
        KokoroModel.voice(id: UserDefaults.standard.string(forKey: Pref.localVoice)) ?? KokoroModel.voice(id: KokoroModel.defaultVoice)!
    }

    func choose(_ voice: KokoroModel.Voice) {
        UserDefaults.standard.set(voice.id, forKey: Pref.localVoice)
        objectWillChange.send()
    }

    /// Looks at the folder again, for when Settings opens.
    func refresh() {
        if case .downloading = state { return }
        state = Self.installedState()
    }

    func engine(voice: KokoroModel.Voice? = nil) -> KokoroEngine? {
        guard isReady else { return nil }
        return KokoroEngine(folder: Self.folder, voice: voice ?? self.voice)
    }

    // MARK: Download

    func download() {
        guard task == nil else { return }
        let total = KokoroModel.totalBytes
        let folder = Self.folder
        let wanted = KokoroModel.missing(in: folder)
        guard !wanted.isEmpty else { state = .ready; return }
        state = .downloading(bytes: 0, of: total)
        task = Task {
            defer { task = nil }
            do {
                try Self.ensureRoom(for: wanted.reduce(0) { $0 + $1.size }, in: folder)
                var finished = total - wanted.reduce(0) { $0 + $1.size }
                for file in wanted {
                    try Task.checkCancellation()
                    let base = finished
                    try await Self.fetch(file, into: folder) { [weak self] written in
                        Task { @MainActor in self?.progress(base + written, total) }
                    }
                    finished += file.size
                    progress(finished, total)
                }
                state = KokoroModel.missing(in: folder).isEmpty ? .ready : .failed("Some files are still missing. Try again.")
            } catch is CancellationError {
                state = Self.installedState()
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func progress(_ bytes: Int, _ total: Int) {
        if case .downloading = state { state = .downloading(bytes: min(bytes, total), of: total) }
    }

    func cancelDownload() { task?.cancel() }

    /// Removes the downloaded model and voices. Only this app's own folder; it can be downloaded again.
    func remove() {
        cancelDownload()
        let folder = Self.folder
        guard folder.lastPathComponent == "Kokoro", folder.deletingLastPathComponent().lastPathComponent == "Hot Take" else { return }
        try? FileManager.default.removeItem(at: folder)
        state = Self.installedState()
    }

    private static func ensureRoom(for bytes: Int, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("voices"), withIntermediateDirectories: true)
        let free = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        if let free, Int(free) < bytes + 200_000_000 {
            throw LocalVoiceProblem.noRoom(needed: bytes)
        }
    }

    /// Downloads one file, checks its size and SHA-256, and only then puts it where the model will look. Nothing unchecked is kept.
    private static func fetch(_ file: KokoroModel.File, into folder: URL, progress: @escaping @Sendable (Int) -> Void) async throws {
        guard let url = KokoroModel.url(for: file) else { throw LocalVoiceProblem.unknownFile }
        let downloader = FileDownloader(progress: progress)
        let partial = try await NetworkGuard.allowing { try await downloader.fetch(url, into: folder) }
        defer { try? FileManager.default.removeItem(at: partial) }
        let size = (try? FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? Int) ?? 0
        guard size == file.size else { throw LocalVoiceProblem.wrongFile(file.path) }
        let checked = try await Task.detached(priority: .utility) { try KokoroModel.sha256(of: partial) }.value
        guard checked == file.sha256 else { throw LocalVoiceProblem.wrongFile(file.path) }
        let destination = folder.appendingPathComponent(file.path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
    }
}

enum LocalVoiceProblem: LocalizedError {
    case noRoom(needed: Int)
    case unknownFile
    case wrongFile(String)
    case notDownloaded
    case silent

    var errorDescription: String? {
        switch self {
        case .noRoom(let needed):
            "There is not enough free space for the voice (about \(ByteCountFormatter.string(fromByteCount: Int64(needed), countStyle: .file)))."
        case .unknownFile: "Hot Take does not know that file."
        case .wrongFile(let name): "The download of \(name) did not match what Hot Take expects, so it was not kept. Try again."
        case .notDownloaded: "The on-device voice has not been downloaded yet. Do that in Settings ▸ Voice."
        case .silent: "The voice made no sound for this text."
        }
    }
}

/// Downloads one address to a file in `folder`, reporting bytes as they arrive, following redirects (Hugging Face serves the large
/// files from its own storage hosts) but only over HTTPS. What arrives is checked by the caller, so where it came from is not trusted.
private final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Int) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var failure: Error?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    init(progress: @escaping @Sendable (Int) -> Void) { self.progress = progress }

    func fetch(_ url: URL, into folder: URL) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        destination = folder.appendingPathComponent(".download-\(UUID().uuidString)")
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let task = session.downloadTask(with: url)
                self.task = task
                task.resume()
            }
        } onCancel: { [weak self] in
            self?.task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(Int(totalBytesWritten))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The system removes `location` when this returns, so the file is moved at once.
        guard let destination else { return }
        if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, status != 200 {
            failure = URLError(.badServerResponse)
            return
        }
        do { try FileManager.default.moveItem(at: location, to: destination) } catch { failure = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error = error ?? failure {
            if let destination { try? FileManager.default.removeItem(at: destination) }
            continuation.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
        } else if let destination {
            continuation.resume(returning: destination)
        } else {
            continuation.resume(throwing: URLError(.unknown))
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
}

// MARK: Speaking

/// Runs Kokoro for one voice. The model is loaded the first time a line is spoken and let go of afterwards, because it holds a few
/// hundred megabytes of the GPU's memory that nothing else needs once the voiceover is made.
actor KokoroRuntime {
    private let folder: URL
    private let voice: KokoroModel.Voice
    private var engine: KokoroTTS?
    private var style: MLXArray?

    init(folder: URL, voice: KokoroModel.Voice) {
        self.folder = folder
        self.voice = voice
    }

    func speak(_ chunks: [String], speed: Float) throws -> [Float] {
        let (engine, style) = try load()
        var pieces: [[Float]] = []
        for chunk in chunks { pieces += try render(chunk, engine, style, speed, depth: 0) }
        return LocalSpeech.joined(pieces)
    }

    private func load() throws -> (KokoroTTS, MLXArray) {
        if let engine, let style { return (engine, style) }
        guard KokoroModel.missing(in: folder).isEmpty else { throw LocalVoiceProblem.notDownloaded }
        let weights = folder.appendingPathComponent(KokoroModel.weights.path)
        let styles = try MLX.loadArrays(url: folder.appendingPathComponent(voice.file.path))
        guard let style = styles["voice"] ?? styles.values.first else { throw LocalVoiceProblem.notDownloaded }
        let engine = KokoroTTS(modelPath: weights)
        self.engine = engine
        self.style = style
        return (engine, style)
    }

    /// One piece of text as audio. If the model says it is too long, it is split in two at a space and each half is spoken.
    private func render(_ text: String, _ engine: KokoroTTS, _ style: MLXArray, _ speed: Float, depth: Int) throws -> [[Float]] {
        do {
            let (audio, _) = try engine.generateAudio(voice: style, language: voice.isBritish ? .enGB : .enUS, text: text, speed: speed)
            return audio.isEmpty ? [] : [audio]
        } catch KokoroTTS.KokoroTTSError.tooManyTokens where depth < 4 {
            let words = text.split(separator: " ")
            guard words.count > 1 else { throw KokoroTTS.KokoroTTSError.tooManyTokens }
            let middle = words.count / 2
            let first = words[..<middle].joined(separator: " ")
            let second = words[middle...].joined(separator: " ")
            return try render(first, engine, style, speed, depth: depth + 1) + render(second, engine, style, speed, depth: depth + 1)
        }
    }

    func release() {
        engine = nil
        style = nil
        MLX.GPU.clearCache()
    }
}

/// A voice on this Mac, as a `SpeechEngine`. Quicker than real time on an Apple silicon GPU, and nothing leaves the Mac.
final class KokoroEngine: SpeechEngine, @unchecked Sendable {
    let fileExtension = "wav"
    let supportsSpeed = true
    var speedRange: ClosedRange<Double> { LocalSpeech.speedRange }

    private let runtime: KokoroRuntime

    init(folder: URL, voice: KokoroModel.Voice) { runtime = KokoroRuntime(folder: folder, voice: voice) }

    func speak(text: String, speed: Double, previous: String?, next: String?) async throws -> Data {
        let chunks = LocalSpeech.chunks(of: text)
        guard !chunks.isEmpty else { throw SpeechFailure.lineRefused("there was nothing to say") }
        do {
            let samples = try await runtime.speak(chunks, speed: Float(min(LocalSpeech.speedRange.upperBound, max(LocalSpeech.speedRange.lowerBound, speed))))
            guard !samples.isEmpty else { throw LocalVoiceProblem.silent }
            return LocalSpeech.wav(samples)
        } catch LocalVoiceProblem.silent {
            throw SpeechFailure.lineRefused(LocalVoiceProblem.silent.localizedDescription)
        } catch let problem as LocalVoiceProblem {
            throw SpeechFailure.stop(problem.localizedDescription)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SpeechFailure.lineRefused("the on-device voice could not say that (\(error))")
        }
    }

    func finish() async { await runtime.release() }
}

/// What `Hot Take --voice-check` does: speaks a sentence with the downloaded voice and reports it. Exit 0 spoke it, 1 failed, 2 not downloaded.
enum VoiceCheck {
    @MainActor
    static func run(writeTo out: URL?, download: Bool) async -> Int32 {
        let store = LocalVoiceStore.shared
        store.refresh()
        if download, !store.isReady {
            store.download()
            var last = -1
            while case .downloading(let bytes, let total) = store.state {
                let percent = bytes * 100 / max(1, total)
                if percent != last, percent % 10 == 0 { print("downloading… \(percent)%"); last = percent }
                try? await Task.sleep(for: .milliseconds(500))
            }
            if case .failed(let message) = store.state { print("FAIL: \(message)"); return 1 }
        }
        guard store.isReady, let engine = store.engine() else {
            print("The on-device voice is not downloaded. Download it in Settings ▸ Voice, then run this again.")
            return 2
        }
        let text = "To share your recording, click Export, then choose a format. It takes just a moment."
        do {
            let started = Date()
            let data = try await engine.speak(text: text, speed: 1, previous: nil, next: nil)
            let elapsed = Date().timeIntervalSince(started)
            await engine.finish()
            let seconds = Double(data.count - 44) / Double(KokoroModel.sampleRate * 2)
            print(String(format: "ok: %@ spoke %.1f s of audio in %.1f s (%d bytes)", store.voice.name, seconds, elapsed, data.count))
            if let out { try data.write(to: out); print("wrote \(out.path)") }
            return seconds > 1 ? 0 : 1
        } catch {
            print("FAIL: \(error.localizedDescription)")
            return 1
        }
    }
}
