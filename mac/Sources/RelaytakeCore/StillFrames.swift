import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Pictures taken out of a recording: an animated GIF of a stretch of it, and a still at each click. Both read
// the video and write new files; the recording itself is never changed.

public enum GIFExporter {
    /// The most frames one GIF holds, so a long stretch at a high rate cannot fill the disk.
    public static let maxFrames = 450
    public static let lengths: [Double] = [3, 5, 10, 15, 30]
    public static let sizes: [(name: String, width: Int)] = [("Small", 480), ("Medium", 640), ("Large", 800)]
    public static let rates: [Double] = [8, 10, 12, 15]

    /// When each frame of a GIF is taken: `length` seconds from `start`, at `fps`, never past the end of the
    /// video and never more than `maxFrames`. Empty when there is nothing left to show.
    public static func frameTimes(start: Double, length: Double, duration: Double, fps: Double) -> [Double] {
        let begin = min(max(0, start), max(0, duration))
        let end = min(duration, begin + max(0, length))
        let step = 1 / max(1, fps)
        guard end - begin >= step else { return [] }
        let count = min(maxFrames, Int(((end - begin) / step).rounded(.down)))
        return (0..<count).map { begin + Double($0) * step }
    }

    public enum GIFError: LocalizedError {
        case nothingToShow
        case failed
        public var errorDescription: String? {
            switch self {
            case .nothingToShow: "There is not enough video from the playhead to make a GIF. Move the playhead earlier."
            case .failed: "The GIF could not be made."
            }
        }
    }

    /// Writes a looping GIF of `length` seconds of `asset` starting at `start`. The picture is scaled down to
    /// `maxWidth` (never up). The file appears only when complete.
    public static func export(
        asset: AVAsset, start: Double, length: Double, fps: Double, maxWidth: Int, to url: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        let duration = try await asset.load(.duration).seconds
        let times = frameTimes(start: start, length: length, duration: duration, fps: fps)
        guard !times.isEmpty else { throw GIFError.nothingToShow }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: 4_000)
        let slack = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = slack
        generator.requestedTimeToleranceAfter = slack

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = url.deletingLastPathComponent().appendingPathComponent(".relaytake-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: partial) }
        guard let destination = CGImageDestinationCreateWithURL(partial as CFURL, UTType.gif.identifier as CFString, times.count, nil)
        else { throw GIFError.failed }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]
        ] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1 / fps]] as CFDictionary

        for (index, time) in times.enumerated() {
            try Task.checkCancellation()
            let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
            CGImageDestinationAddImage(destination, image, frameProperties)
            progress(Double(index + 1) / Double(times.count))
        }
        guard CGImageDestinationFinalize(destination) else { throw GIFError.failed }
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: partial)
        } else {
            try FileManager.default.moveItem(at: partial, to: url)
        }
    }
}

public enum ClickFrames {
    /// The moments to take a picture at: one per click, in order, skipping a click that comes within
    /// `minimumGap` seconds of the one before (a double-click is one picture). Clicks past the end are dropped.
    public static func moments(clicks: [ClickEvent], duration: Double, minimumGap: Double = 1) -> [Double] {
        var result: [Double] = []
        for click in clicks.sorted(by: { $0.time < $1.time }) {
            guard click.time >= 0, click.time <= duration else { continue }
            if let last = result.last, click.time - last < minimumGap { continue }
            result.append(click.time)
        }
        return result
    }

    /// "Click 03 at 0m12s.png": numbered so they sort in order, with the moment in the name.
    public static func fileName(number: Int, of total: Int, time: Double) -> String {
        let digits = max(2, String(total).count)
        let whole = Int(time.rounded(.down))
        return "Click \(String(format: "%0\(digits)d", number)) at \(whole / 60)m\(String(format: "%02d", whole % 60))s.png"
    }

    /// The folder name for a take's pictures.
    public static func folderName(for title: String) -> String {
        let clean = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean.isEmpty ? "Recording" : clean) + " – click frames"
    }

    /// A folder inside `parent` that does not exist yet, named for the take.
    public static func uniqueFolder(in parent: URL, title: String, fileManager: FileManager = .default) -> URL {
        let base = folderName(for: title)
        var candidate = parent.appendingPathComponent(base, isDirectory: true)
        var number = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(base) \(number)", isDirectory: true)
            number += 1
        }
        return candidate
    }

    /// Saves a PNG of each of `times` into `folder` (made if needed). Returns the files written.
    public static func export(
        asset: AVAsset, times: [Double], to folder: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let duration = try await asset.load(.duration).seconds
        var written: [URL] = []
        for (index, time) in times.enumerated() {
            try Task.checkCancellation()
            // Right at the very end there may be no frame; the last one will do.
            let at = min(time, max(0, duration - 0.04))
            let image = try await generator.image(at: CMTime(seconds: at, preferredTimescale: 600)).image
            let url = folder.appendingPathComponent(fileName(number: index + 1, of: times.count, time: time))
            try Screenshot.writePNG(image, to: url)
            written.append(url)
            progress(Double(index + 1) / Double(times.count))
        }
        return written
    }
}
