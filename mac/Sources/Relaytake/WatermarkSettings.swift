import AppKit
import RelaytakeCore
import SwiftUI
import UniformTypeIdentifiers

/// The watermark chosen in Settings ▸ Watermark. Off by default. Read each time a video is previewed or saved.
enum WatermarkPreferences {
    static let enabled = "watermarkEnabled"
    /// "app" (the Hot Take logo, the default), "custom" (an image the person chose) or "none".
    static let logo = "watermarkLogo"
    static let logoPath = "watermarkLogoPath"
    static let text = "watermarkText"
    static let corner = "watermarkCorner"
    static let size = "watermarkSize"
    static let opacity = "watermarkOpacity"

    /// The watermark to draw, or nil when it is off or has nothing to show.
    static func current(_ defaults: UserDefaults = .standard) -> Watermark? {
        guard defaults.bool(forKey: enabled) else { return nil }
        let image: CGImage?
        switch defaults.string(forKey: logo) ?? "app" {
        case "none": image = nil
        case "custom": image = defaults.string(forKey: logoPath).flatMap(customLogo)
        default: image = appLogo()
        }
        let mark = Watermark(
            logo: image, text: defaults.string(forKey: text) ?? "Hot Take",
            corner: WatermarkCorner(rawValue: defaults.string(forKey: corner) ?? "") ?? .topLeft,
            size: defaults.object(forKey: size) as? Double ?? Watermark.defaultSize,
            opacity: defaults.object(forKey: opacity) as? Double ?? Watermark.defaultOpacity)
        return mark.isEmpty ? nil : mark
    }

    static func appLogo() -> CGImage? {
        let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
            ?? NSApp?.applicationIconImage
        var rect = CGRect(x: 0, y: 0, width: 512, height: 512)
        return icon?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func customLogo(path: String) -> CGImage? {
        guard !path.isEmpty, let image = NSImage(contentsOfFile: path) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

struct WatermarkPane: View {
    @AppStorage(WatermarkPreferences.enabled) private var enabled = false
    @AppStorage(WatermarkPreferences.logo) private var logo = "app"
    @AppStorage(WatermarkPreferences.logoPath) private var logoPath = ""
    @AppStorage(WatermarkPreferences.text) private var text = "Hot Take"
    @AppStorage(WatermarkPreferences.corner) private var corner = WatermarkCorner.topLeft.rawValue
    @AppStorage(WatermarkPreferences.size) private var size = Watermark.defaultSize
    @AppStorage(WatermarkPreferences.opacity) private var opacity = Watermark.defaultOpacity

    var body: some View {
        Form {
            Section {
                Toggle("Add a watermark to saved videos", isOn: $enabled)
                    .help("Draws a logo and a name in one corner of every video you save or export. The recording itself is never changed.")
            } footer: {
                Text("Shown in the Studio preview and drawn into saved copies and exports. Screenshots are not watermarked.")
            }

            if enabled {
                Section {
                    Picker("Logo", selection: $logo) {
                        Text("Hot Take logo").tag("app")
                        Text("My image").tag("custom")
                        Text("None").tag("none")
                    }
                    if logo == "custom" {
                        LabeledContent("Image") {
                            HStack {
                                Text(logoPath.isEmpty ? "Not chosen" : (logoPath as NSString).lastPathComponent)
                                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                Button("Choose…") { chooseImage() }
                            }
                        }
                        .help("A PNG, JPEG or HEIC picture. A square picture with a transparent background works best.")
                    }
                    TextField("Name", text: $text)
                        .help("Words shown beside the logo. Leave empty to show only the logo.")
                } header: {
                    Text("What to show")
                }

                Section {
                    Picker("Corner", selection: $corner) {
                        ForEach(WatermarkCorner.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }
                    LabeledContent("Size") {
                        Slider(value: $size, in: Watermark.sizeRange)
                    }
                    LabeledContent("Opacity") {
                        Slider(value: $opacity, in: Watermark.opacityRange)
                    }
                } header: {
                    Text("Where and how big")
                }
            }
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, -12)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a picture to use as your watermark logo."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard WatermarkPreferences.customLogo(path: url.path) != nil else {
            NSSound.beep()
            return
        }
        logoPath = url.path
    }
}
