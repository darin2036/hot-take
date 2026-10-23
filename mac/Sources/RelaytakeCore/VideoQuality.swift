import Foundation

public extension EncodingSettings {
    /// Bits per pixel the presets use for screen recordings (Medium is 1080p at 24 fps and 1600 kbps).
    static let bitsPerPixel = 0.032

    /// A video bitrate (kbps, in steps of 50) that fits a resolution and frame rate, so changing either
    /// changes the file size the way you would expect. The same rule the Small, Medium and Large
    /// presets follow.
    static func suggestedVideoKbps(resolution: Int, fps: Int) -> Int {
        let short = max(240, min(2160, resolution)) / 2 * 2
        let long = (short * 16 / 9) / 2 * 2
        let rate = Double(long * short * max(5, min(60, fps))) * bitsPerPixel / 1000
        return max(200, min(20000, Int((rate / 50).rounded()) * 50))
    }
}

public enum VideoQuality: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large, custom
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var longEdge: Int { switch self { case .small: 1280; case .medium: 1920; case .large: 2560; case .custom: 1920 } }
    public var shortEdge: Int { longEdge * 9 / 16 }
    public var fps: Int { self == .small ? 15 : self == .large ? 30 : 24 }
    public var videoBitrate: Int { self == .small ? 700_000 : self == .large ? 3_500_000 : 1_600_000 }
    public var audioBitrate: Int { self == .small ? 64_000 : self == .large ? 128_000 : 96_000 }
    public var channels: Int { self == .small ? 1 : 2 }
    public func estimatedMB(seconds: Double, audio: Bool = true) -> Double {
        max(0, seconds) * Double(videoBitrate + (audio ? audioBitrate : 0)) / 8_000_000
    }
    public func dimensions(width: Double, height: Double) -> (width: Int, height: Int) {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return (2, 2) }
        let landscape = width >= height
        let ratio = min(1, min(Double(landscape ? longEdge : shortEdge) / width, Double(landscape ? shortEdge : longEdge) / height))
        return (max(2, Int(width * ratio) / 2 * 2), max(2, Int(height * ratio) / 2 * 2))
    }
}


/// Immutable snapshot used by capture/export, independent of changes to Settings mid-job.
public struct EncodingSettings: Sendable {
    public let longEdge: Int
    public let shortEdge: Int
    public let fps: Int
    public let videoBitrate: Int
    public let audioBitrate: Int
    public let channels: Int

    public init(resolution: Int = 1080, fps: Int = 24, videoKbps: Int = 1600, audioKbps: Int = 96, channels: Int = 2) {
        shortEdge = max(240, min(2160, resolution)) / 2 * 2
        longEdge = (shortEdge * 16 / 9) / 2 * 2
        self.fps = max(5, min(60, fps))
        videoBitrate = max(200, min(20000, videoKbps)) * 1000
        self.channels = channels == 1 ? 1 : 2
        audioBitrate = max(32, min(256, audioKbps)) * 1000
    }
    public init(preset: VideoQuality) {
        self.init(resolution: preset.shortEdge, fps: preset.fps,
                  videoKbps: preset.videoBitrate / 1000, audioKbps: preset.audioBitrate / 1000, channels: preset.channels)
    }
    public func estimatedMB(seconds: Double, audio: Bool = true) -> Double {
        max(0, seconds) * Double(videoBitrate + (audio ? audioBitrate : 0)) / 8_000_000
    }
    public func dimensions(width: Double, height: Double) -> (width: Int, height: Int) {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return (2, 2) }
        let landscape = width >= height
        let ratio = min(1, min(Double(landscape ? longEdge : shortEdge) / width, Double(landscape ? shortEdge : longEdge) / height))
        return (max(2, Int(width * ratio) / 2 * 2), max(2, Int(height * ratio) / 2 * 2))
    }
}
