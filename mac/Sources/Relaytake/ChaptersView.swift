import AppKit
import RelaytakeCore
import SwiftUI

/// The parts of the recording on screen, shown as headings inside its transcript. Hot Take can suggest them from what
/// is said; the suggestions are only a starting point and nothing is saved until you use them. Once saved, every
/// chapter can be renamed, moved to the current moment, removed, and more can be added anywhere.
@MainActor
final class ChapterBook: ObservableObject {
    @Published private(set) var saved: [Chapter] = []
    /// Suggestions waiting for a decision. Shown in place of `saved`, and editable like it, but not written anywhere.
    @Published var proposal: [Chapter]?
    @Published private(set) var status: String?
    @Published private(set) var notes: [String] = []
    @Published var problem = ""
    @Published var confirmReplace = false
    @Published var confirmClear = false
    /// A chapter just added at the playhead: its title opens for typing.
    @Published private(set) var newID: UUID?
    @Published private(set) var copied = false

    private var take: TakeEntry?
    private var library: LibraryModel?
    private var player: PlayerModel?

    var shown: [Chapter] { proposal ?? saved }

    private var duration: TimeInterval? {
        guard let take, let player else { return nil }
        let known = player.duration > 0 ? player.duration : TakeLibrary.metadata(for: take.files)?.durationSeconds ?? 0
        return known > 0 ? known : nil
    }

    func load(_ take: TakeEntry, library: LibraryModel, player: PlayerModel) {
        self.take = take
        self.library = library
        self.player = player
        saved = TakeLibrary.metadata(for: take.files)?.chapters ?? []
        proposal = nil
        notes = []
        problem = ""
        newID = nil
    }

    /// Applies a change to the suggestions if some are showing, otherwise to the saved chapters (and saves them).
    func change(_ edit: (inout [Chapter]) -> Void) {
        guard let take else { return }
        problem = ""
        if var list = proposal {
            edit(&list)
            proposal = ChapterList.normalized(list, duration: duration)
        } else {
            var list = saved
            edit(&list)
            do {
                saved = try TakeLibrary.saveChapters(list, for: take, duration: duration)
                library?.refresh()
            } catch { problem = "Could not save the chapters: \(error.localizedDescription)" }
        }
    }

    func rename(_ id: UUID, to title: String) {
        change { list in if let i = list.firstIndex(where: { $0.id == id }) { list[i].title = title } }
    }

    func remove(_ id: UUID) { change { $0.removeAll { $0.id == id } } }

    func addAtPlayhead() {
        guard let player else { return }
        let chapter = Chapter(start: player.time, title: "New chapter")
        newID = chapter.id
        change { $0.append(chapter) }
        if !shown.contains(where: { $0.id == chapter.id }) { problem = "There is already a chapter at this moment." }
    }

    func moveToPlayhead(_ id: UUID) {
        guard let player else { return }
        let before = shown.count
        change { list in if let i = list.firstIndex(where: { $0.id == id }) { list[i].start = player.time } }
        // Moving onto another chapter's moment would leave two in one place, so tidying drops one.
        if shown.count < before { problem = "There is already a chapter at this moment." }
    }

    /// Finds chapters from what is said. `done` runs afterwards, since a transcript may have been made along the way.
    func suggest(done: @escaping @MainActor () -> Void) {
        guard status == nil, let target = take else { return }
        problem = ""
        notes = []
        status = "Starting…"
        Task {
            defer { status = nil }
            let result = await ChapterAnalysis.run(for: target) { self.status = $0 }
            library?.refresh()
            guard target.id == take?.id else { return }
            notes = result.notes
            if !result.chapters.isEmpty { proposal = result.chapters }
            done()
        }
    }

    func useProposal() {
        guard let proposal, let take else { return }
        do {
            saved = try TakeLibrary.saveChapters(proposal, for: take, duration: duration)
            self.proposal = nil
            notes = []
            library?.refresh()
        } catch { problem = "Could not save the chapters: \(error.localizedDescription)" }
    }

    func copyTimestamps() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ChapterList.timestampList(shown), forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }
}

/// The transcript header's Chapters menu: suggest, add at the current moment, copy, remove all.
struct ChapterActionsMenu: View {
    @ObservedObject var book: ChapterBook
    let suggested: @MainActor () -> Void

    var body: some View {
        Menu {
            Button("Suggest Chapters", systemImage: "sparkles") { book.suggest(done: suggested) }
                .disabled(book.status != nil)
                .help("Find where the subject changes, on this Mac. You choose what to keep, and can change any of it afterwards.")
            Button("Add Chapter Here", systemImage: "plus") { book.addAtPlayhead() }
                .disabled(book.status != nil)
                .help("Start a chapter at the current moment of the video")
            Divider()
            Button("Copy Chapter Timestamps", systemImage: "doc.on.doc") { book.copyTimestamps() }.disabled(book.shown.isEmpty)
            Button("Remove All Chapters…", systemImage: "trash", role: .destructive) { book.confirmClear = true }
                .disabled(book.saved.isEmpty || book.proposal != nil)
        } label: { Label("Chapters", systemImage: "list.bullet.rectangle") }
            .labelStyle(.iconOnly)
            .menuIndicator(.hidden).fixedSize()
            .help("Chapters: headings in the transcript that split the recording into parts")
            .accessibilityLabel("Chapters")
    }
}

/// What the chapters are doing right now: suggestions waiting for a decision, work in progress, and anything to know.
struct ChapterStatus: View {
    @ObservedObject var book: ChapterBook

    var body: some View {
        if book.proposal != nil { proposalBar }
        if let status = book.status {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(status).font(.caption).foregroundStyle(.secondary) }
        }
        if book.copied { Label("Chapter timestamps copied", systemImage: "checkmark").font(.caption).foregroundStyle(.green) }
        if !book.problem.isEmpty { Text(book.problem).font(.caption).foregroundStyle(.red) }
        ForEach(book.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
    }

    private var proposalBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Suggested chapters. Not saved yet.", systemImage: "sparkles").font(.callout.weight(.medium))
            Text("They are shown in the transcript. Rename, move or remove any of them first if you like.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(book.saved.isEmpty ? "Use These Chapters" : "Replace My Chapters…") {
                    if book.saved.isEmpty { book.useProposal() } else { book.confirmReplace = true }
                }
                .buttonStyle(.borderedProminent)
                Button("Discard") { book.proposal = nil }
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    /// The questions the chapters ask before replacing or removing what was saved.
    func chapterDialogs(_ book: ChapterBook) -> some View { modifier(ChapterDialogs(book: book)) }
}

private struct ChapterDialogs: ViewModifier {
    @ObservedObject var book: ChapterBook

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Replace your chapters?", isPresented: $book.confirmReplace) {
                Button("Replace", role: .destructive) { book.useProposal() }
            } message: {
                Text("The \(book.saved.count) chapters you have now, including any changes you made, are replaced by the \(book.proposal?.count ?? 0) suggested ones.")
            }
            .confirmationDialog("Remove all chapters?", isPresented: $book.confirmClear) {
                Button("Remove All", role: .destructive) { book.change { $0 = [] } }
            } message: {
                Text("The video is not changed.")
            }
    }
}

/// A chapter as a heading in the transcript: its start time (click to go there) and its title (click to rename;
/// Return or clicking away saves).
struct ChapterHeading: View {
    let chapter: Chapter
    @ObservedObject var book: ChapterBook
    /// Not observed: a heading only acts on the player, so it need not redraw as the video plays.
    let player: PlayerModel

    @State private var title = ""
    @FocusState private var focused: Bool

    private var suggested: Bool { book.proposal != nil }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(ChapterList.timestamp(chapter.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            TextField("Chapter title", text: $title)
                .textFieldStyle(.plain)
                .font(.headline)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, now in if !now { commit() } }
                .accessibilityLabel("Chapter title, starts at \(ChapterList.timestamp(chapter.start))")
            if suggested {
                Image(systemName: "sparkles").font(.caption).foregroundStyle(.tint).help("Suggested, not saved yet")
            }
            Menu {
                Button("Play from Here", systemImage: "play") { player.play(from: chapter.start) }
                Button("Move to Current Time", systemImage: "arrow.right.to.line") { book.moveToPlayhead(chapter.id) }
                Divider()
                Button("Delete Chapter", systemImage: "trash", role: .destructive) { book.remove(chapter.id) }
            } label: { Image(systemName: "ellipsis") }
                .menuIndicator(.hidden).fixedSize().buttonStyle(.borderless)
                .accessibilityLabel("Chapter actions")
        }
        .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 4)
        .overlay(alignment: .top) { Divider().padding(.horizontal, 8) }
        .background(suggested ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { player.seek(to: chapter.start) }
        .help("Click the time to jump here. Click the title to rename it.")
        .onAppear {
            title = chapter.title
            if book.newID == chapter.id { focused = true }
        }
        .onChange(of: chapter.title) { _, new in if !focused { title = new } }
    }

    private func commit() {
        let cleaned = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if cleaned.isEmpty || cleaned == chapter.title { title = chapter.title } else { book.rename(chapter.id, to: cleaned) }
    }
}

/// Jump to a chapter of the recording being watched. Absent when the recording has none.
struct ChapterMenu: View {
    let chapters: [Chapter]
    @ObservedObject var player: PlayerModel

    var body: some View {
        if !chapters.isEmpty {
            let active = ChapterList.activeIndex(in: chapters, at: player.time)
            Menu {
                ForEach(Array(chapters.enumerated()), id: \.element.id) { position, chapter in
                    Button { player.play(from: chapter.start) } label: {
                        Text("\(ChapterList.timestamp(chapter.start))  \(chapter.title)")
                        if active == position { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                Label("Chapters", systemImage: "list.bullet.rectangle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Jump to a chapter")
        }
    }
}
