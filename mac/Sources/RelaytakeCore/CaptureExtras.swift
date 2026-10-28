import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Small pure helpers for recording and playback: what to keep out of a capture, how screenshots are named and
// saved, the speeds offered for playback, and how long a speaker's notes take to read.

public enum CaptureExclusions {
    /// The system process that draws notification banners.
    public static let notificationCenter = "com.apple.notificationcenterui"

    /// Apps left out of a screen or area capture. Hot Take's own windows are out unless the recording is of
    /// the app itself; with `hideNotifications`, Notification Center is out as well, so a banner that pops up
    /// during a recording is not in it.
    public static func bundleIdentifiers(ownApp: String?, includeOwnApp: Bool, hideNotifications: Bool) -> [String] {
        var ids: [String] = []
        if !includeOwnApp, let ownApp { ids.append(ownApp) }
        if hideNotifications { ids.append(notificationCenter) }
        return ids
    }
}

public enum Screenshot {
    /// "Hot Take Screenshot 2026-10-21 at 09.30.15.png": dots, not colons, as takes are named.
    public static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "Hot Take Screenshot %04d-%02d-%02d at %02d.%02d.%02d.png",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// A name for `date` that nothing in `directory` already uses ("… 2.png", "… 3.png"), so two shots in one
    /// second never overwrite each other.
    public static func uniqueURL(in directory: URL, for date: Date, fileManager: FileManager = .default, calendar: Calendar = .current) -> URL {
        let name = fileName(for: date, calendar: calendar)
        let stem = (name as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(name)
        var number = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem) \(number).png")
            number += 1
        }
        return candidate
    }

    public enum WriteError: LocalizedError {
        case failed
        public var errorDescription: String? { "The screenshot could not be saved." }
    }

    /// Writes `image` as a PNG, in one piece: a failed write leaves no half-file behind.
    public static func writePNG(_ image: CGImage, to url: URL) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw WriteError.failed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw WriteError.failed }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (data as Data).write(to: url, options: .atomic)
    }
}

public enum PlaybackSpeed {
    public static let choices: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    public static let normal = 1.0

    /// "1×", "1.25×", "0.5×".
    public static func label(_ speed: Double) -> String {
        let text = speed == speed.rounded() ? String(Int(speed)) : String(format: "%g", speed)
        return text + "×"
    }

    /// A saved value that is one of the choices, else normal speed.
    public static func valid(_ speed: Double) -> Double { choices.contains(speed) ? speed : normal }
}

public enum ReadingTime {
    /// Seconds to say `text` aloud at `wordsPerMinute` (a calm speaking pace is about 150).
    public static func seconds(of text: String, wordsPerMinute: Double = 150) -> Double {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return Double(words) / max(1, wordsPerMinute) * 60
    }

    /// "About 1 min 20 s", "About 45 s", or an empty string for no words.
    public static func label(for text: String, wordsPerMinute: Double = 150) -> String {
        let total = Int(seconds(of: text, wordsPerMinute: wordsPerMinute).rounded())
        guard total > 0 else { return "" }
        if total < 60 { return "About \(total) s" }
        let minutes = total / 60, rest = total % 60
        return rest == 0 ? "About \(minutes) min" : "About \(minutes) min \(rest) s"
    }
}
