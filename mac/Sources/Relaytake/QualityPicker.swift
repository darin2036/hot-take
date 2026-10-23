import RelaytakeCore
import SwiftUI

enum EncodingPreferences {
    static func resolve(_ preset: VideoQuality) -> EncodingSettings {
        guard preset == .custom else { return EncodingSettings(preset: preset) }
        let defaults = UserDefaults.standard
        func number(_ key: String, _ fallback: Int) -> Int { defaults.object(forKey: key) as? Int ?? fallback }
        let resolution = number("customResolution", 1080), fps = number("customFPS", 24)
        // Someone who typed their own bitrate before "Auto" existed keeps it.
        let auto = defaults.object(forKey: "customAutoBitrate") as? Bool ?? (defaults.object(forKey: "customVideoKbps") == nil)
        let video = auto ? EncodingSettings.suggestedVideoKbps(resolution: resolution, fps: fps) : number("customVideoKbps", 1600)
        return EncodingSettings(resolution: resolution, fps: fps, videoKbps: video,
            audioKbps: number("customAudioKbps", 96), channels: number("customChannels", 2))
    }
}

struct QualityPicker: View {
    @AppStorage("customResolution") private var resolution = 1080
    @AppStorage("customFPS") private var fps = 24
    @AppStorage("customVideoKbps") private var videoKbps = 1600
    @AppStorage("customAutoBitrate") private var autoBitrate = true
    @AppStorage("customAudioKbps") private var audioKbps = 96
    @AppStorage("customChannels") private var channels = 2
    @Binding var value: String
    var seconds: Double = 60
    var audio = true
    var recording = false
    /// A compact drop-down (with the size per minute in each choice) instead of the segmented bar.
    var menu = false
    /// Shown beside the size menu (the record sheet puts the microphone here).
    var accessory: AnyView?
    private var quality: EncodingSettings {
        if value == "custom" {
            return EncodingSettings(
                resolution: resolution, fps: fps, videoKbps: effectiveVideoKbps, audioKbps: audioKbps, channels: channels)
        }
        return EncodingSettings(preset: VideoQuality(rawValue: value) ?? .medium)
    }
    /// The bitrate in use: worked out from the resolution and frame rate, or the one typed in.
    private var effectiveVideoKbps: Int {
        autoBitrate ? EncodingSettings.suggestedVideoKbps(resolution: resolution, fps: fps) : videoKbps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if menu {
                HStack(spacing: 12) {
                    if let accessory { accessory }
                    Picker("File size", selection: $value) {
                        ForEach(VideoQuality.allCases) { q in Text(menuTitle(q)).tag(q.rawValue) }
                    }.pickerStyle(.menu)
                        .help("Smaller files use less disk space. Small: quick sharing. Medium: everyday recording. Large: more detail. Custom: choose your own settings.")
                }
            } else {
                Picker("File size", selection: $value) {
                    ForEach(VideoQuality.allCases) { q in Text(q.title).tag(q.rawValue) }
                }.pickerStyle(.segmented)
                    .help("Small: quick sharing. Medium: everyday recording. Large: more detail. Custom: choose your own settings.")
            }
            if value == "custom" {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Resolution").foregroundStyle(.secondary)
                        Picker("Resolution", selection: $resolution) {
                            ForEach([360, 480, 720, 1080, 1440, 2160], id: \.self) { Text("\($0)p").tag($0) }
                        }.labelsHidden()
                        Text("Frame rate").foregroundStyle(.secondary)
                        LiveNumberField(label: "Frames per second", value: $fps, range: 5...60)
                    }
                    GridRow {
                        Text("Video (kbps)").foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            LiveNumberField(
                                label: "Video bitrate in kbps",
                                value: Binding(get: { effectiveVideoKbps }, set: { videoKbps = $0 }), range: 200...20000)
                                .disabled(autoBitrate)
                            Toggle("Auto", isOn: Binding(get: { autoBitrate }, set: { on in
                                if !on { videoKbps = effectiveVideoKbps }  // start from what Auto was using
                                autoBitrate = on
                            }))
                            .toggleStyle(.checkbox)
                            .help("Work out the bitrate from the resolution and frame rate, so changing either changes the file size")
                        }
                        Text("Audio (kbps)").foregroundStyle(.secondary)
                        Picker("Audio bitrate in kbps", selection: $audioKbps) {
                            ForEach([32, 48, 64, 96, 128, 192, 256], id: \.self) { Text("\($0)").tag($0) }
                        }.labelsHidden().disabled(!audio)
                    }
                    GridRow {
                        Text("Channels").foregroundStyle(.secondary)
                        Picker("Audio channels", selection: $channels) {
                            Text("Mono").tag(1); Text("Stereo").tag(2)
                        }.labelsHidden().disabled(!audio)
                    }
                }.font(.system(size: 12)).controlSize(.small)
            }
            if !menu || value == "custom" {
                Text(summary)
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Estimated size from the bitrate. Recordings of a mostly still screen usually come out smaller.")
            }
        }
        .onAppear {
            // A bitrate typed before "Auto" existed stays in charge.
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "customAutoBitrate") == nil, defaults.object(forKey: "customVideoKbps") != nil {
                autoBitrate = false
            }
        }
    }
    private func menuTitle(_ preset: VideoQuality) -> String {
        guard preset != .custom else { return preset.title }
        let mb = EncodingSettings(preset: preset).estimatedMB(seconds: 60, audio: audio)
        return "\(preset.title) · about \(ByteCountFormatter.string(fromByteCount: Int64(mb * 1_000_000), countStyle: .file)) a minute"
    }

    private var summary: String {
        let size = ByteCountFormatter.string(
            fromByteCount: Int64((quality.estimatedMB(seconds: seconds, audio: audio) * 1_000_000).rounded()),
            countStyle: .file)
        return recording ? "About \(size) per minute" : "Estimated copy: \(size)"
    }


}

/// A number box that applies each digit as it is typed, so anything that depends on it (such as the
/// estimated file size) updates at once. Out-of-range numbers are held to the range when you leave the box.
struct LiveNumberField: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $text)
            .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 72)
            .focused($focused)
            .accessibilityLabel(label).help("\(range.lowerBound)–\(range.upperBound)")
            .onAppear { text = String(value) }
            .onChange(of: text) { _, new in
                // Digits only; the value follows while typing, held inside the range.
                let digits = new.filter(\.isNumber)
                if digits != new { text = digits; return }
                if let number = Int(digits) { value = min(range.upperBound, max(range.lowerBound, number)) }
            }
            .onChange(of: value) { _, new in if !focused { text = String(new) } }
            .onChange(of: focused) { _, isFocused in if !isFocused { text = String(value) } }
            .onSubmit { text = String(value) }
    }
}
