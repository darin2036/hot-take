import SwiftUI

/// Help ▸ Hot Take Help. The text lives in Resources/Help.md (copied into the app bundle by bundle.sh);
/// each "## " heading is a topic in the sidebar.
enum HelpContent {
    struct Topic: Identifiable {
        let title: String
        var lines: [Changelog.Line]
        var id: String { title }

        func matches(_ query: String) -> Bool {
            title.localizedCaseInsensitiveContains(query) || lines.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
    }

    static var source: String? {
        guard let url = Bundle.main.url(forResource: "Help", withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func parse(_ markdown: String) -> [Topic] {
        var text = markdown
        while let start = text.range(of: "<!--"), let end = text.range(of: "-->", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
        var topics: [Topic] = []
        for line in Changelog.parse(text) {
            if case .section(let title) = line {
                topics.append(Topic(title: title, lines: []))
            } else if !topics.isEmpty {
                topics[topics.count - 1].lines.append(line)
            }
        }
        return topics
    }
}

extension Changelog.Line {
    var text: String {
        switch self {
        case .title(let s), .section(let s), .subsection(let s), .bullet(let s), .text(let s): s
        }
    }
}

struct HelpView: View {
    private let topics = HelpContent.source.map(HelpContent.parse) ?? []
    @State private var query = ""
    @State private var selection: String?

    private var shown: [HelpContent.Topic] { query.isEmpty ? topics : topics.filter { $0.matches(query) } }
    private var current: HelpContent.Topic? { shown.first { $0.id == selection } ?? shown.first }

    var body: some View {
        NavigationSplitView {
            List(shown, selection: $selection) { topic in
                Text(topic.title).tag(topic.id)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 280)
            .overlay {
                if topics.isEmpty == false, shown.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        } detail: {
            if topics.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Help isn't included in this build.").font(.title2.bold())
                    Text("Rebuild the app with scripts/bundle.sh, or read the guide on the project page.")
                        .foregroundStyle(.secondary)
                    Link("Open the project page", destination: AppInfo.repository)
                }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(current.title).font(.largeTitle.bold())
                        ForEach(Array(current.lines.enumerated()), id: \.offset) { _, line in row(line) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .textSelection(.enabled)
                }
                .id(current.id)
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search Help")
        .frame(minWidth: 640, idealWidth: 780, minHeight: 420, idealHeight: 600)
    }

    @ViewBuilder private func row(_ line: Changelog.Line) -> some View {
        switch line {
        case .subsection(let s): Text(s).font(.title3.bold()).padding(.top, 8)
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(s)).fixedSize(horizontal: false, vertical: true)
            }
        case .text(let s): Text(inline(s)).fixedSize(horizontal: false, vertical: true)
        case .title, .section: EmptyView()
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnly))) ?? AttributedString(s)
    }
}

/// Replaces the system's empty Help menu with Hot Take Help and What's New.
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Hot Take Help") { show("help") }
                .keyboardShortcut("?", modifiers: .command)
            Button("What's New") { show("whats-new") }
        }
    }

    private func show(_ id: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}
