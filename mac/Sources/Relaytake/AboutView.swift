import AppKit
import SwiftUI

/// Where the project lives. Links open in the browser; the app itself never touches the network.
enum AppInfo {
    static let repository = URL(string: "https://github.com/darin2036/hot-take")!
    static var issues: URL { repository.appendingPathComponent("issues") }
    static var license: URL { repository.appendingPathComponent("blob/main/LICENSE") }
    static var notices: URL { repository.appendingPathComponent("blob/main/THIRD_PARTY_NOTICES.md") }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }

    /// Version, system and Mac model: what a bug report needs, copied only when you ask.
    static var supportDetails: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let build = build.isEmpty ? "" : " (\(build))"
        return "Hot Take \(version)\(build)\nSystem: \(os)\nMac model: \(String(cString: model))"
    }
}

/// The About window: what Hot Take is, its promises, and where to find the source.
struct AboutView: View {
    @State private var copied = false

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 88, height: 88)
            VStack(spacing: 2) {
                Text("Hot Take").font(.largeTitle.bold())
                Text("Version \(AppInfo.version)\(AppInfo.build.isEmpty ? "" : " (\(AppInfo.build))") · pre-release")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("Show it. Say it. Keep it yours.").font(.title3.italic()).foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    promise("lock.shield", "Your recordings stay on your Mac. There is no account, no analytics, and no server run by the project.")
                    promise("wifi.slash", "The app refuses every web request it makes. You can check that yourself from the command line (see the README).")
                    promise("cpu", "Captions, titles, summaries and suggested edits are made on-device with the system's speech and language models.")
                    promise("cursorarrow.click", "To suggest zooms it notes where and when you click, never what you clicked on or typed.")
                }
                .padding(4).frame(maxWidth: .infinity, alignment: .leading)
            } label: { Text("Private by design").font(.headline) }

            Grid(horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Link(destination: AppInfo.repository) { Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                    Link(destination: AppInfo.issues) { Label("Report an issue", systemImage: "exclamationmark.bubble") }
                }
                GridRow {
                    Link(destination: AppInfo.license) { Label("MIT license", systemImage: "doc.text") }
                    Link(destination: AppInfo.notices) { Label("Third-party notices", systemImage: "shippingbox") }
                }
            }
            .font(.callout).labelStyle(.titleAndIcon)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(AppInfo.supportDetails, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            } label: { Label(copied ? "Copied" : "Copy version details for a bug report", systemImage: copied ? "checkmark" : "doc.on.doc") }
                .controlSize(.small)
                .help("Copies the app version, system version and Mac model. Nothing else, and nothing is sent anywhere.")

            Divider()
            VStack(spacing: 3) {
                Text("© 2026 Darin Laframboise. Released under the MIT license.")
                Text("Not affiliated with any other product or company.")
            }
            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 480)
    }

    private func promise(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 20)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}

/// Replaces the standard "About" menu item so it opens the window above.
struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Hot Take") { openWindow(id: "about") }
        }
    }
}
