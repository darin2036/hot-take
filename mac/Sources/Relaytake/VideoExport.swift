import AVFoundation
import Foundation
import RelaytakeCore

/// Recording masters remain MP4; these are portable exports of the current edit.
enum VideoExportFormat: String, CaseIterable, Identifiable {
    case mp4, mov, webm
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mp4: "MP4 — Most compatible"
        case .mov: "MOV — For video editors"
        case .webm: "WebM — Smaller files"
        }
    }
    var available: Bool { self != .webm || VideoExport.encoder != nil }
}

enum VideoExport {
    /// Distributors may supply a self-contained encoder; development builds look in common install locations.
    static var encoder: URL? {
        let candidates = [Bundle.main.url(forAuxiliaryExecutable: "ffmpeg"),
            URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"), URL(fileURLWithPath: "/usr/local/bin/ffmpeg")]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func save(asset: AVAsset, segments: [TimeSpan], to destination: URL,
                     format: VideoExportFormat, quality: EncodingSettings, includeAudio: Bool,
                     progress: @escaping @MainActor (Double) -> Void) async throws {
        let fm = FileManager.default
        // Finish alongside the destination before replacing anything the save panel approved.
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".relaytake-export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let output = staging.appendingPathComponent("video.\(format.rawValue)")
        if format == .webm {
            guard let encoder else { throw ExportError.failed("WebM needs the optional FFmpeg encoder. MP4 and MOV work without it.") }
            let intermediate = staging.appendingPathComponent("source.mp4")
            try await Exporter.save(asset: asset, segments: segments, to: intermediate, quality: quality, includeAudio: includeAudio) { progress($0 * 0.5) }
            try await encodeWebM(encoder: encoder, source: intermediate, output: output, quality: quality, includeAudio: includeAudio)
        } else {
            try await Exporter.save(asset: asset, segments: segments, to: output, quality: quality, includeAudio: includeAudio, progress: progress)
        }
        try Task.checkCancellation()
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: output)
        } else {
            try fm.moveItem(at: output, to: destination)
        }
        await progress(1)
    }

    private static func encodeWebM(encoder: URL, source: URL, output: URL, quality: EncodingSettings, includeAudio: Bool) async throws {
        let process = Process()
        process.executableURL = encoder
        process.arguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-n", "-i", source.path,
            "-map", "0:v:0", "-map", "0:a:0?", "-c:v", "libvpx-vp9", "-b:v", String(quality.videoBitrate),
            "-crf", "32", "-deadline", "good", "-cpu-used", "4", "-row-mt", "1", "-pix_fmt", "yuv420p"]
            + (includeAudio ? ["-c:a", "libopus", "-b:a", String(quality.audioBitrate), "-ac", String(quality.channels)] : ["-an"])
            + [output.path]
        // File-backed diagnostics avoid pipe backpressure on long exports.
        let log = output.deletingLastPathComponent().appendingPathComponent("encoder.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        process.standardError = handle
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        do {
            while process.isRunning {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(100))
            }
        } catch {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            throw error
        }
        guard process.terminationStatus == 0 else {
            throw ExportError.failed("Could not encode WebM. Check that FFmpeg includes the VP9 and Opus encoders, or export MP4.")
        }
    }
}
