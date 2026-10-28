import AppKit
import RelaytakeCore
import SwiftUI

/// The parts of the recording on screen, shown as headings inside its transcript with the lines under each as its body.
/// Hot Take can find them from what is said. Every chapter can be renamed, moved to the current moment or removed,
/// and one can be started at any line.
@MainActor
final class ChapterBook: ObservableObject {
    @Published private(set) var saved: [Chapter] = []
    /// Whether this recording's transcript shows chapters: its own choice if it has one, otherwise the Settings default.
    @Published private(set) var enabled = true
    @Published private(set) var status: String?
    @Published private(set) var notes: [String] = []
    @Published var problem = ""
    @Published var confirmReplace = false
    @Published var confirmClear = false
    /// A chapter just added at the playhead: its title opens for typing.
    private var newID: UUID?
    @Published private(set) var copied = false

    private var take: TakeEntry?
    private var library: LibraryModel?
    private var player: PlayerModel?

    /// The chapters on screen: none while they are turned off (the saved ones are kept).
    var shown: [Chapter] { enabled ? saved : [] }

    private var duration: TimeInterval? {
        guard let take, let player else { return nil }
        let known = player.duration > 0 ? player.duration : TakeLibrary.metadata(for: take.files)?.durationSeconds ?? 0
        return known > 0 ? known : nil
    }

    func load(_ take: TakeEntry, library: LibraryModel, player: PlayerModel) {
        self.take = take
        self.library = library
        self.player = player
        let metadata = TakeLibrary.metadata(for: take.files)
        saved = metadata?.chapters ?? []
        enabled = metadata?.chaptersEnabled ?? Pref.chaptersByDefault
        pending = nil
        notes = []
        problem = ""
        newID = nil
    }

    /// Applies a change to the chapters and saves them.
    func change(_ edit: (inout [Chapter]) -> Void) {
        guard let take else { return }
        problem = ""
        var list = saved
        edit(&list)
        do {
            saved = try TakeLibrary.saveChapters(list, for: take, duration: duration)
            // Taking out the last one means no chapters wanted here, so they are not found again on the next visit.
            if saved.isEmpty { try TakeLibrary.update(take) { $0.chaptersEnabled = false }; enabled = false }
            library?.refresh()
        } catch { problem = "Could not save the chapters: \(error.localizedDescription)" }
    }

    /// True once for a chapter just added, so its title opens for typing there and not each time it scrolls into view.
    func takeNew(_ id: UUID) -> Bool {
        guard newID == id else { return false }
        newID = nil
        return true
    }

    func rename(_ id: UUID, to title: String) {
        change { list in if let i = list.firstIndex(where: { $0.id == id }) { list[i].title = title } }
    }

    func remove(_ id: UUID) { change { $0.removeAll { $0.id == id } } }

    func addAtPlayhead() { if let player { add(at: player.time) } }

    /// Starts a chapter at a moment, its title open for typing.
    func add(at time: TimeInterval) {
        turnOn()
        let chapter = Chapter(start: time, title: "New chapter")
        newID = chapter.id
        change { $0.append(chapter) }
        if !shown.contains(where: { $0.id == chapter.id }) { problem = "There is already a chapter here." }
    }

    func moveToPlayhead(_ id: UUID) {
        guard let player else { return }
        let before = shown.count
        change { list in if let i = list.firstIndex(where: { $0.id == id }) { list[i].start = player.time } }
        // Moving onto another chapter's moment would leave two in one place, so tidying drops one.
        if shown.count < before { problem = "There is already a chapter at this moment." }
    }

    /// Turns chapters on or off for this recording. Off hides them and stops them being found; nothing is deleted.
    func setEnabled(_ on: Bool, found: @escaping @MainActor () -> Void) {
        guard let take else { return }
        do {
            try TakeLibrary.update(take) { $0.chaptersEnabled = on }
            enabled = on
            library?.refresh()
            if on, saved.isEmpty { find(automatic: true, done: found) }
        } catch { problem = "Could not change chapters: \(error.localizedDescription)" }
    }

    /// Asking for chapters (finding or adding one) turns them back on for this recording.
    private func turnOn() {
        guard !enabled, let take else { return }
        try? TakeLibrary.update(take) { $0.chaptersEnabled = true }
        enabled = true
    }

    /// Finds chapters by itself for a recording that has a transcript, none yet and chapters on. Quiet when there is nothing to find.
    func findAutomatically(done: @escaping @MainActor () -> Void) {
        guard enabled, saved.isEmpty, status == nil, let take,
              !(TakeLibrary.metadata(for: take.files)?.transcript ?? []).isEmpty else { return }
        find(automatic: true, done: done)
    }

    /// Chapters found from what is said, waiting only for the go-ahead to replace ones already there.
    private var pending: [Chapter]?

    /// Finds chapters from what is said. Done at once when there are none yet; otherwise asks before replacing yours.
    /// `done` runs afterwards, since a transcript may have been made along the way.
    func suggest(done: @escaping @MainActor () -> Void) {
        guard status == nil else { return }
        turnOn()
        find(automatic: false, done: done)
    }

    private func find(automatic: Bool, done: @escaping @MainActor () -> Void) {
        guard status == nil, let target = take else { return }
        problem = ""
        notes = []
        status = "Starting…"
        Task {
            defer { status = nil }
            let result = await ChapterAnalysis.run(for: target) { self.status = $0 }
            library?.refresh()
            guard target.id == take?.id else { return }
            // Looking by itself says nothing when there is nothing to find; asked, it says why.
            if !automatic { notes = result.notes }
            if !result.chapters.isEmpty {
                pending = result.chapters
                if saved.isEmpty { useFound() } else { confirmReplace = true }
            }
            done()
        }
    }

    var foundCount: Int { pending?.count ?? 0 }

    func useFound() {
        guard let pending, let take else { return }
        do {
            saved = try TakeLibrary.saveChapters(pending, for: take, duration: duration)
            self.pending = nil
            library?.refresh()
        } catch { problem = "Could not save the chapters: \(error.localizedDescription)" }
    }

    func discardFound() { pending = nil }

    func copyTimestamps() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ChapterList.timestampList(shown), forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }
}

/// The icon alone in a box of one size, so a button and a menu come out the same however the system pads each.
private struct ToolbarGlyphStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.icon.frame(width: 20, height: 16)    }
}

extension View {
    /// An icon-only button or menu in the transcript's header: all the same size, named by a tooltip (which waits a moment
    /// before it shows) and by its accessibility label.
    func toolbarIcon(_ tip: String) -> some View {
        labelStyle(ToolbarGlyphStyle())
            .buttonStyle(.bordered)
            .menuIndicator(.hidden)
            .controlSize(.regular)
            .fixedSize()
            .help(tip)
            .accessibilityLabel(tip)
    }
}

/// The transcript header's Chapters menu: suggest, add at the current moment, copy, remove all.
struct ChapterActionsMenu: View {
    @ObservedObject var book: ChapterBook
    let suggested: @MainActor () -> Void

    var body: some View {
        Menu {
            Toggle("Chapters", isOn: Binding(get: { book.enabled }, set: { book.setEnabled($0, found: suggested) }))
                .disabled(book.status != nil)
                .help("Show chapters in this transcript. Turning them off keeps any you have saved. New recordings follow the setting in Settings.")
            Divider()
            Button("Find Chapters", systemImage: "sparkles") { book.suggest(done: suggested) }
                .disabled(book.status != nil)
                .help("Find where the subject changes, on this Mac. Every chapter can be renamed, moved or removed afterwards.")
            Button("Add Chapter Here", systemImage: "plus") { book.addAtPlayhead() }
                .disabled(book.status != nil)
                .help("Start a chapter at the current moment of the video. You can also right-click a line.")
            Divider()
            Button("Copy Chapter Timestamps", systemImage: "doc.on.doc") { book.copyTimestamps() }.disabled(book.shown.isEmpty)
            Button("Remove All Chapters…", systemImage: "trash", role: .destructive) { book.confirmClear = true }
                .disabled(book.saved.isEmpty)
        } label: { Label("Chapters", systemImage: "list.bullet.rectangle") }
            .toolbarIcon("Chapters: headings that split the transcript into parts")
    }
}

/// What the chapters are doing right now: suggestions waiting for a decision, work in progress, and anything to know.
struct ChapterStatus: View {
    @ObservedObject var book: ChapterBook

    var body: some View {
        if let status = book.status {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(status).font(.caption).foregroundStyle(.secondary) }
        }
        if book.copied { Label("Chapter timestamps copied", systemImage: "checkmark").font(.caption).foregroundStyle(.green) }
        if !book.problem.isEmpty { Text(book.problem).font(.caption).foregroundStyle(.red) }
        ForEach(book.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
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
                Button("Replace", role: .destructive) { book.useFound() }
                Button("Keep Mine", role: .cancel) { book.discardFound() }
            } message: {
                Text("The \(book.saved.count) chapters you have now, including any changes you made, are replaced by the \(book.foundCount) found.")
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
    /// The title is words until it is double-clicked (or Rename is chosen); Return or clicking away then saves it and
    /// puts it back. A chapter just added starts open for its name.
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(ChapterList.timestamp(chapter.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if editing {
                TextField("Chapter title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                    .focused($focused)
                    .onSubmit { finish(save: true) }
                    .onExitCommand { finish(save: false) }
                    .onChange(of: focused) { _, now in if !now { finish(save: true) } }
                    .task { focused = true }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1.5))
                    .accessibilityLabel("Chapter title, starts at \(ChapterList.timestamp(chapter.start))")
            } else {
                Text(chapter.title.isEmpty ? "Untitled chapter" : chapter.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(chapter.title.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture(count: 2).onEnded { begin() })
                    .accessibilityLabel("Chapter, \(chapter.title), starts at \(ChapterList.timestamp(chapter.start))")
                    .accessibilityAction(named: "Rename") { begin() }
            }
            Menu {
                Button("Play from Here", systemImage: "play") { player.play(from: chapter.start) }
                Button("Rename", systemImage: "pencil") { begin() }
                Button("Move to Current Time", systemImage: "arrow.right.to.line") { book.moveToPlayhead(chapter.id) }
                Divider()
                Button("Delete Chapter", systemImage: "trash", role: .destructive) { book.remove(chapter.id) }
            } label: { Image(systemName: "ellipsis") }
                .menuIndicator(.hidden).fixedSize().buttonStyle(.borderless)
                .accessibilityLabel("Chapter actions")
        }
        .padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 4)
        .overlay(alignment: .top) { Divider().padding(.horizontal, 8) }
        .contentShape(Rectangle())
        .onTapGesture { player.seek(to: chapter.start) }
        .help("Click to jump here. Double-click the title to rename it.")
        .onAppear { if book.takeNew(chapter.id) { begin() } }
    }

    private func begin() {
        title = chapter.title
        editing = true
        focused = true
    }

    /// Ends the edit. The new title is kept unless it was cancelled, emptied or left as it was.
    private func finish(save: Bool) {
        guard editing else { return }
        editing = false
        focused = false
        let cleaned = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if save, !cleaned.isEmpty, cleaned != chapter.title { book.rename(chapter.id, to: cleaned) }
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
