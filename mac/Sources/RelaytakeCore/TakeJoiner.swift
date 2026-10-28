import AVFoundation
import CoreGraphics
import Foundation

// Joining several recordings into one, and bringing a video that was not recorded here into the library.
// Both leave the originals untouched and write a new file.

public enum JoinPlan {
    /// The picture size of a joined take: the largest width and the largest height, made even for the encoder.
    public static func renderSize(for sizes: [CGSize]) -> CGSize {
        func even(_ value: CGFloat) -> CGFloat { max(2, (value / 2).rounded(.up) * 2) }
        return CGSize(width: even(sizes.map(\.width).max() ?? 2), height: even(sizes.map(\.height).max() ?? 2))
    }

    /// Whether the clips must be re-encoded to share a picture size. Clips that already match are joined
    /// as they are, with no loss.
    public static func needsReencode(sizes: [CGSize]) -> Bool {
        guard let first = sizes.first else { return false }
        return sizes.contains { abs($0.width - first.width) > 1 || abs($0.height - first.height) > 1 }
    }

    /// Scales `source` to fit inside `canvas` without distortion and centers it (bars fill what is left).
    public static func fit(_ source: CGSize, into canvas: CGSize) -> CGAffineTransform {
        guard source.width > 0, source.height > 0 else { return .identity }
        let scale = min(canvas.width / source.width, canvas.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2))
    }

    /// The clicks of each recording laid on the joined timeline: each clip's clicks move later by the length of
    /// everything before it, so Auto Zoom and click rings still land on the right moments.
    public static func mergedClicks(_ parts: [(clicks: [ClickEvent], duration: Double)]) -> [ClickEvent] {
        var offset = 0.0
        var result: [ClickEvent] = []
        for part in parts {
            result += part.clicks.filter { $0.time >= 0 && $0.time <= part.duration }
                .map { ClickEvent(time: $0.time + offset, x: $0.x, y: $0.y) }
            offset += part.duration
        }
        return result
    }

    /// "A + B" for two, "A + B + 1 more" beyond that: a title for a joined take, kept short.
    public static func title(for titles: [String]) -> String {
        let names = titles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return "Joined takes" }
        func short(_ name: String) -> String { name.count > 28 ? String(name.prefix(27)) + "…" : name }
        switch names.count {
        case 1: return short(names[0])
        case 2: return short(names[0]) + " + " + short(names[1])
        default: return short(names[0]) + " + " + short(names[1]) + " + \(names.count - 2) more"
        }
    }
}

public enum JoinError: LocalizedError {
    case needsTwo
    case noVideo(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .needsTwo: "Choose at least two recordings to join."
        case .noVideo(let name): "“\(name)” has no video to join."
        case .failed(let why): why
        }
    }
}

public enum TakeJoiner {
    /// Joins the recordings end to end, in the order given, into one MP4 at `destination`. A file already
    /// there is replaced only once the new one is complete.
    public static func join(
        _ urls: [URL], to destination: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        guard urls.count >= 2 else { throw JoinError.needsTwo }
        let composition = AVMutableComposition()
        var videoTrack: AVMutableCompositionTrack?
        var audioTracks: [AVMutableCompositionTrack] = []
        var cursor = CMTime.zero
        var clips: [(range: CMTimeRange, size: CGSize, transform: CGAffineTransform)] = []

        for url in urls {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard let source = try await asset.loadTracks(withMediaType: .video).first, duration.seconds > 0 else {
                throw JoinError.noVideo(url.deletingPathExtension().lastPathComponent)
            }
            let transform = try await source.load(.preferredTransform)
            let natural = try await source.load(.naturalSize)
            let oriented = CGRect(origin: .zero, size: natural).applying(transform)
            if videoTrack == nil { videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) }
            let range = CMTimeRange(start: .zero, duration: duration)
            try videoTrack?.insertTimeRange(range, of: source, at: cursor)
            for (index, audio) in try await asset.loadTracks(withMediaType: .audio).enumerated() {
                if index == audioTracks.count,
                   let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    audioTracks.append(track)
                }
                if index < audioTracks.count { try audioTracks[index].insertTimeRange(range, of: audio, at: cursor) }
            }
            clips.append((CMTimeRange(start: cursor, duration: duration), CGSize(width: abs(oriented.width), height: abs(oriented.height)), transform))
            cursor = cursor + duration
        }

        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".relaytake-join-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let output = staging.appendingPathComponent("joined.mp4")

        let sizes = clips.map(\.size)
        if !JoinPlan.needsReencode(sizes: sizes) {
            // Same picture size: join without re-encoding, which is quick and loses nothing. If the pieces do
            // not share a codec, the system refuses, and the slower way below is used instead.
            if (try? await export(composition, video: nil, preset: AVAssetExportPresetPassthrough, to: output, progress: progress)) == nil {
                try? FileManager.default.removeItem(at: output)
                try await export(composition, video: video(composition, clips: clips, sizes: sizes), preset: AVAssetExportPresetHighestQuality, to: output, progress: progress)
            }
        } else {
            try await export(composition, video: video(composition, clips: clips, sizes: sizes), preset: AVAssetExportPresetHighestQuality, to: output, progress: progress)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: output)
        } else {
            try FileManager.default.moveItem(at: output, to: destination)
        }
    }

    /// Each clip scaled to fit one picture size, with bars where its shape differs.
    private static func video(
        _ composition: AVMutableComposition, clips: [(range: CMTimeRange, size: CGSize, transform: CGAffineTransform)], sizes: [CGSize]
    ) -> AVMutableVideoComposition? {
        guard let track = composition.tracks(withMediaType: .video).first else { return nil }
        let canvas = JoinPlan.renderSize(for: sizes)
        let video = AVMutableVideoComposition()
        video.renderSize = canvas
        video.frameDuration = CMTime(value: 1, timescale: 30)
        video.instructions = clips.map { clip in
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = clip.range
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layer.setTransform(clip.transform.concatenating(JoinPlan.fit(clip.size, into: canvas)), at: clip.range.start)
            instruction.layerInstructions = [layer]
            return instruction
        }
        return video
    }

    private static func export(
        _ asset: AVAsset, video: AVVideoComposition?, preset: String, to url: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw JoinError.failed("This Mac cannot join these recordings.")
        }
        session.videoComposition = video
        try? FileManager.default.removeItem(at: url)
        let watcher = Task {
            for await state in session.states(updateInterval: 0.2) {
                if case .exporting(let value) = state { progress(value.fractionCompleted) }
            }
        }
        defer { watcher.cancel() }
        try await session.export(to: url, as: .mp4)
    }
}

public enum ImportError: LocalizedError {
    case notAVideo(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notAVideo(let name): "“\(name)” is not a video Hot Take can read."
        case .failed(let why): why
        }
    }
}

public enum VideoImporter {
    /// File types offered when importing. The picture is brought in as an MP4, as every take is.
    public static let fileExtensions = ["mp4", "mov", "m4v"]

    /// A take name from the file's name that nothing in `directory` is using ("Demo", "Demo 2", …).
    public static func baseName(for source: URL, in directory: URL, fileManager: FileManager = .default) -> String {
        var stem = source.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while stem.hasPrefix(".") { stem.removeFirst() }
        if stem.isEmpty { stem = "Imported video" }
        func taken(_ name: String) -> Bool {
            let files = TakeFiles(directory: directory, baseName: name)
            return [files.video, files.metadata, files.captions].contains { fileManager.fileExists(atPath: $0.path) }
        }
        var candidate = stem
        var number = 2
        while taken(candidate) {
            candidate = "\(stem) \(number)"
            number += 1
        }
        return candidate
    }

    /// Copies (or, for a MOV or M4V, converts) a video into `directory` as a new take, with a notes file
    /// that names it after the file. The source is only read.
    public static func importVideo(from source: URL, into directory: URL) async throws -> TakeFiles {
        let name = source.deletingPathExtension().lastPathComponent
        let asset = AVURLAsset(url: source)
        guard (try? await asset.load(.isReadable)) == true,
              let duration = try? await asset.load(.duration), duration.seconds > 0,
              (try? await asset.loadTracks(withMediaType: .video).first) != nil
        else { throw ImportError.notAVideo(name) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = TakeFiles(directory: directory, baseName: baseName(for: source, in: directory))
        let staging = directory.appendingPathComponent(".relaytake-processing", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: staged) }

        if source.pathExtension.lowercased() == "mp4" {
            try FileManager.default.copyItem(at: source, to: staged)
        } else if (try? await convert(asset, to: staged, preset: AVAssetExportPresetPassthrough)) == nil {
            // The pictures or sound in this file cannot go into an MP4 as they are: encode them.
            try? FileManager.default.removeItem(at: staged)
            do { try await convert(asset, to: staged, preset: AVAssetExportPresetHighestQuality) }
            catch { throw ImportError.failed("“\(name)” could not be converted to MP4: \(error.localizedDescription)") }
        }
        try FileManager.default.moveItem(at: staged, to: files.video)

        let metadata = TakeMetadata(title: name, summary: "", created: Date(), durationSeconds: duration.seconds)
        try metadata.encoded().write(to: files.metadata, options: .atomic)
        return files
    }

    private static func convert(_ asset: AVAsset, to url: URL, preset: String) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ImportError.failed("This Mac cannot convert that file.")
        }
        try await session.export(to: url, as: .mp4)
    }
}
