import SwiftUI

/// The change log, shown from Help ▸ What's New. The app bundle carries a copy of CHANGELOG.md.
enum Changelog {
    enum Line: Identifiable {
        case title(String), section(String), subsection(String), bullet(String), text(String)
        var id: UUID { UUID() }
    }

    static var source: String? {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func parse(_ markdown: String) -> [Line] {
        markdown.split(separator: "\n", omittingEmptySubsequences: true).compactMap { raw in
            let line = String(raw)
            if line.hasPrefix("### ") { return .subsection(String(line.dropFirst(4))) }
            if line.hasPrefix("## ") { return .section(String(line.dropFirst(3)).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")) }
            if line.hasPrefix("# ") { return nil }
            if line.hasPrefix("- ") { return .bullet(String(line.dropFirst(2))) }
            return .text(line)
        }
    }
}

struct WhatsNewView: View {
    private let lines = Changelog.source.map(Changelog.parse)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("What's New in Hot Take").font(.largeTitle.bold())
                Text("Version \(AppInfo.version)\(AppInfo.build.isEmpty ? "" : " (\(AppInfo.build))")")
                    .font(.callout).foregroundStyle(.secondary)
                if let lines {
                    ForEach(lines) { line in row(line) }
                } else {
                    Text("The change log isn't included in this build. You can read it on the project page.")
                        .foregroundStyle(.secondary)
                    Link("Open the change log", destination: AppInfo.repository.appendingPathComponent("blob/main/CHANGELOG.md"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .textSelection(.enabled)
        }
        .frame(minWidth: 480, idealWidth: 620, minHeight: 360, idealHeight: 640)
    }

    @ViewBuilder private func row(_ line: Changelog.Line) -> some View {
        switch line {
        case .title(let s): Text(s).font(.title.bold())
        case .section(let s): Text(s).font(.title2.bold()).padding(.top, 14)
        case .subsection(let s): Text(s).font(.headline).padding(.top, 6)
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(s)).fixedSize(horizontal: false, vertical: true)
            }
        case .text(let s): Text(inline(s)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnly))) ?? AttributedString(s)
    }
}
