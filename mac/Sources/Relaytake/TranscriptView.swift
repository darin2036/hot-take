import AppKit
import RelaytakeCore
import SwiftUI
import Translation
import UniformTypeIdentifiers

/// The words of a recording next to its video. Click a line to jump there; the line being spoken
/// is highlighted and followed as the video plays.
struct TranscriptView: View {
    let take: TakeEntry
    @ObservedObject var library: LibraryModel
    @ObservedObject var player: PlayerModel

    @State private var segments: [CaptionSegment] = []
    @State private var loaded = false
    /// Find: opened from Edit > Find in Transcript (⌘F). Matching lines are tinted and Return / ⌘G steps through them.
    @State private var findOpen = false
    @State private var query = ""
    @State private var matchPosition = 0
    @State private var scrollTick = 0
    @FocusState private var findFocused: Bool
    @FocusState private var editFocused: Bool
    @State private var status: String?
    @StateObject private var summaryJob = SummaryJob()
    /// The summary card above the transcript; collapsed once, it stays collapsed.
    @AppStorage("transcriptSummaryOpen") private var summaryOpen = true
    /// Width of the transcript column beside the video; dragged with the divider and remembered.
    @AppStorage("transcriptPaneWidth") private var paneWidth = 380.0
    private static let minPane = 260.0
    private static let minVideo = 260.0
    @State private var problem = ""
    /// The recording's chapters, shown as headings among the lines.
    @StateObject private var chapters = ChapterBook()
    /// The line being corrected, and what it says so far. Double-click a line to start; Return or clicking away saves.
    @State private var editingIndex: Int?
    @State private var draft = ""
    @State private var confirmRemake = false
    @State private var savedNote = false
    /// Translations of this take's transcript by language, and the one on screen (nil is what was said).
    @State private var translations: [String: [CaptionSegment]] = [:]
    @State private var shown: String?
    @State private var targets: [CaptionTranslator.Language] = []
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var job: TranslationJob?

    /// What a translation in progress is for, kept so a take opened meanwhile is not written to by mistake.
    private struct TranslationJob {
        let take: TakeEntry
        let language: String
        let segments: [CaptionSegment]
    }

    /// The lines on screen: the translation if one is chosen, otherwise the transcript.
    private var lines: [CaptionSegment] { shown.flatMap { translations[$0] } ?? segments }
    private var showingTranslation: Bool { shown.flatMap { translations[$0] } != nil }

    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Indices of the lines containing the search text, in order.
    private var matches: [Int] {
        guard findOpen, !term.isEmpty else { return [] }
        return lines.indices.filter { lines[$0].text.localizedCaseInsensitiveContains(term) }
    }

    private var currentMatch: Int? {
        let all = matches
        return all.isEmpty ? nil : all[min(matchPosition, all.count - 1)]
    }

    private var activeIndex: Int? {
        lines.lastIndex { $0.start <= player.time + 0.05 && player.time < $0.end + 0.05 }
    }

    var body: some View {
        GeometryReader { proxy in
            // The video always keeps at least `minVideo`; the transcript can be as narrow as `minPane`.
            let maxPane = max(Self.minPane, proxy.size.width - Self.minVideo - 15)
            let width = min(max(paneWidth, Self.minPane), maxPane)
            HStack(alignment: .top, spacing: 0) {
                PlayerView(player: player.player, fileURL: take.files.video)
                    .frame(minWidth: Self.minVideo, maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black).clipShape(RoundedRectangle(cornerRadius: 8))
                PaneDivider(width: $paneWidth, range: Self.minPane...maxPane, current: width)
                VStack(alignment: .leading, spacing: 10) {
                    header
                    if segments.isEmpty && chapters.shown.isEmpty { empty } else { list }
                }
                .frame(width: width, alignment: .topLeading).frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(16)
        .task(id: take.id) {
            editingIndex = nil; closeFind(); reload()
            chapters.load(take, library: library, player: player)
            chapters.findAutomatically { }
        }
        .chapterDialogs(chapters)
        .task { targets = await CaptionTranslator.targets(excluding: SpeechPreferences.locale.language) }
        .translationTask(translationConfig) { session in await runTranslation(session) }
        .focusedSceneValue(\.transcriptFind, segments.isEmpty ? nil : TranscriptFindActions(
            show: openFind, next: { stepMatch(1) }, previous: { stepMatch(-1) }))
        .confirmationDialog("Regenerate the transcript?", isPresented: $confirmRemake) {
            Button("Regenerate", role: .destructive) { make() }
        } message: {
            Text("The AI built into your Mac will listen to the recording again and write a fresh transcript. It replaces the current one, including any corrections you made. Nothing leaves this Mac.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                if !segments.isEmpty {
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(lines.map(\.text).joined(separator: "\n"), forType: .string)
                    }
                    .toolbarIcon(showingTranslation ? "Copy the whole translation" : "Copy the whole transcript")
                    translateMenu
                    Button { summaryJob.run(for: take, library: library); summaryOpen = true } label: { Label("Summarize", systemImage: "sparkles") }
                        .disabled(summaryJob.isRunning || status != nil || Summarizer.availabilityMessage != nil)
                        .toolbarIcon(Summarizer.availabilityMessage.map { "Can't summarize: \($0)" }
                            ?? "Summarize with AI: read the whole transcript and write a short summary, on this Mac")
                    Button(role: .none) { confirmRemake = true } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
                        .disabled(status != nil)
                        .toolbarIcon("Regenerate the transcript: the on-device AI listens to the recording again and replaces it")
                }
                if loaded { ChapterActionsMenu(book: chapters) { if segments.isEmpty { reload() } } }
            }
            ChapterStatus(book: chapters)
            if savedNote {
                Label("Saved", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            }
            if findOpen { findBar }
            summaryCard
            if let status {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            if !problem.isEmpty { Text(problem).font(.caption).foregroundStyle(.red) }
        }
    }

    /// The take's summary above the transcript, so a long recording can be understood without reading every line.
    @ViewBuilder private var summaryCard: some View {
        let summary = TakeLibrary.metadata(for: take.files)?.summary ?? ""
        let _ = summaryJob.revision
        if summaryJob.isRunning || !summary.isEmpty || !summaryJob.note.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Summary").font(.subheadline.weight(.semibold))
                    Spacer()
                    if let working = summaryJob.status {
                        ProgressView().controlSize(.small)
                        Text(working).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        if summaryJob.previous != nil {
                            Button("Undo") { summaryJob.undo(for: take, library: library) }
                                .buttonStyle(.link).font(.caption)
                        }
                        if !summary.isEmpty {
                            Button("Copy", systemImage: "doc.on.doc") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(summary, forType: .string)
                            }
                            .buttonStyle(.borderless).controlSize(.small).help("Copy the summary")
                            Button(summaryOpen ? "Hide" : "Show") { summaryOpen.toggle() }
                                .buttonStyle(.link).font(.caption)
                        }
                    }
                }
                if summaryOpen, !summary.isEmpty {
                    ScrollView {
                        Text(summary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }
                if !summaryJob.note.isEmpty { Text(summaryJob.note).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var findBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find", text: $query)
                .textFieldStyle(.plain)
                .focused($findFocused)
                .onSubmit { stepMatch(1); findFocused = true }
                .onExitCommand(perform: closeFind)
                .onChange(of: query) { _, _ in matchPosition = 0; scrollTick += 1 }
            if !term.isEmpty {
                Text(matches.isEmpty ? "No matches" : "\(min(matchPosition, matches.count - 1) + 1) of \(matches.count)")
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
            }
            Button { stepMatch(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(matches.isEmpty).help("Previous match (⇧⌘G)")
            Button { stepMatch(1) } label: { Image(systemName: "chevron.down") }
                .disabled(matches.isEmpty).help("Next match (⌘G)")
            Button("Done", action: closeFind)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func openFind() {
        findOpen = true
        findFocused = true
    }

    private func closeFind() {
        findOpen = false
        findFocused = false
        query = ""
        matchPosition = 0
    }

    private func stepMatch(_ direction: Int) {
        guard findOpen else { openFind(); return }
        let count = matches.count
        guard count > 0 else { return }
        matchPosition = ((min(matchPosition, count - 1) + direction) % count + count) % count
        scrollTick += 1
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.alignleft").font(.system(size: 30)).foregroundStyle(.secondary)
            Text(loaded ? "No transcript yet." : "Loading…").foregroundStyle(.secondary)
            if loaded {
                Button("Make Transcript") { make() }.disabled(status != nil)
                    .help("Listens to the recording on this Mac. Nothing leaves your Mac.")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let breaks = chapterBreaks
                    ForEach(Array(lines.enumerated()), id: \.offset) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(breaks.byLine[item.offset] ?? []) { ChapterHeading(chapter: $0, book: chapters, player: player) }
                            row(item.offset, item.element)
                                .padding(.leading, item.offset >= breaks.firstLine ? 14 : 0)
                        }
                    }
                    ForEach(breaks.after) { ChapterHeading(chapter: $0, book: chapters, player: player) }
                    if segments.isEmpty, loaded {
                        Button("Make Transcript") { make() }.disabled(status != nil).padding(.top, 8)
                            .help("Listens to the recording on this Mac. Nothing leaves your Mac.")
                    }
                }
            }
            .onChange(of: scrollTick) { _, _ in
                if let line = currentMatch { withAnimation { proxy.scrollTo(line, anchor: .center) } }
            }
            .onChange(of: activeIndex) { _, new in
                if let new, matches.isEmpty, editingIndex == nil { withAnimation { proxy.scrollTo(new, anchor: .center) } }
            }
        }
    }

    /// Each chapter sits just above the first line that starts at or after it; any later than every line go at the end.
    /// `firstLine` is where the first chapter's body begins; lines from there on are indented under their headings.
    private var chapterBreaks: (byLine: [Int: [Chapter]], after: [Chapter], firstLine: Int) {
        var byLine: [Int: [Chapter]] = [:]
        var after: [Chapter] = []
        for chapter in chapters.shown {
            if let line = lines.firstIndex(where: { $0.start + 0.05 >= chapter.start }) {
                byLine[line, default: []].append(chapter)
            } else { after.append(chapter) }
        }
        return (byLine, after, byLine.keys.min() ?? .max)
    }

    @ViewBuilder
    private func row(_ index: Int, _ segment: CaptionSegment) -> some View {
        let active = activeIndex == index
        let found = matches.contains(index)
        let current = currentMatch == index
        if editingIndex == index {
            HStack(alignment: .top, spacing: 10) {
                Text(timeLabel(segment.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).padding(.top, 5)
                // Return or the check mark saves, Escape puts the old words back, and clicking away saves.
                VStack(alignment: .trailing, spacing: 4) {
                    TextField("", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...8)
                        .focused($editFocused)
                        .padding(6)
                        .background(.background, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1.5))
                        .onSubmit { finishEditing(cancelled: false) }
                        .onExitCommand { finishEditing(cancelled: true) }
                        .onChange(of: editFocused) { _, focused in if !focused { finishEditing(cancelled: false) } }
                        .task { editFocused = true }
                        .accessibilityLabel("Transcript line at \(timeLabel(segment.start))")
                    Button { finishEditing(cancelled: false) } label: {
                        Image(systemName: "checkmark.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain).foregroundStyle(.tint)
                    .help("Save (Return)")
                    .accessibilityLabel("Save correction")
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(timeLabel(segment.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(segment.text).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(
                current ? Color.yellow.opacity(0.45)
                    : found ? Color.yellow.opacity(0.2)
                    : active ? Color.accentColor.opacity(0.18) : .clear,
                in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            // A double-click opens the line for editing. A click moves to the line without starting or stopping playback.
            .onTapGesture { player.seek(to: segment.start) }
            .simultaneousGesture(TapGesture(count: 2).onEnded { beginEditing(index) })
            .help("Click to jump to this line. Double-click to edit the words.")
            .contextMenu {
                Button("Edit", systemImage: "pencil") { beginEditing(index) }.disabled(status != nil || showingTranslation)
                Button("Start Chapter Here", systemImage: "text.line.first.and.arrowtriangle.forward") { chapters.add(at: segment.start) }
            }
            .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(named: "Edit this line") { beginEditing(index) }
        }
    }

    private func reload() {
        let metadata = TakeLibrary.metadata(for: take.files)
        segments = metadata?.transcript ?? []
        translations = metadata?.translations ?? [:]
        shown = nil
        loaded = true
    }

    // MARK: Translation

    private var translateMenu: some View {
        Menu {
            if !translations.isEmpty {
                Picker("Show", selection: $shown) {
                    Text("As spoken").tag(String?.none)
                    ForEach(translations.keys.sorted(), id: \.self) { Text(CaptionTranslator.name(for: $0)).tag(Optional($0)) }
                }.pickerStyle(.inline)
                Divider()
            }
            Menu("Translate To") {
                ForEach(targets) { language in
                    Button(translations[language.id] == nil ? language.name : "\(language.name) (translate again)") {
                        translate(to: language.id)
                    }
                }
            }
            if let shown, translations[shown] != nil {
                Divider()
                Button("Save \(CaptionTranslator.name(for: shown)) Captions…") { saveCaptions(language: shown) }
                Button("Remove \(CaptionTranslator.name(for: shown)) Translation", role: .destructive) { removeTranslation(shown) }
            }
        } label: { Label("Translate", systemImage: "translate") }
            .toolbarIcon("Translate the transcript on this Mac")
            .disabled(status != nil || targets.isEmpty)
            .help("Translate the transcript on this Mac. Translations can be used as captions in the Studio.")
    }

    private func translate(to language: String) {
        guard status == nil, !segments.isEmpty else { return }
        problem = ""
        status = "Translating to \(CaptionTranslator.name(for: language))…"
        job = TranslationJob(take: take, language: language, segments: segments)
        let next = TranslationSession.Configuration(
            source: SpeechPreferences.locale.language, target: Locale.Language(identifier: language))
        // The same pair again does not change the configuration, so it has to be invalidated to run once more.
        if translationConfig == next { translationConfig?.invalidate() } else { translationConfig = next }
    }

    /// Runs when the system hands over a session (after any language download the person allowed).
    private func runTranslation(_ session: TranslationSession) async {
        guard let job else { return }
        defer { self.job = nil; status = nil }
        let name = CaptionTranslator.name(for: job.language)
        do {
            let result = try await CaptionTranslator.translate(job.segments, with: session) { done, total in
                Task { @MainActor in status = "Translating to \(name): \(done) of \(total)…" }
            }
            try TakeLibrary.update(job.take) { $0.translations[job.language] = result }
            library.refresh()
            guard job.take.id == take.id else { return }
            translations[job.language] = result
            shown = job.language
        } catch { problem = "Could not translate to \(name): \(error.localizedDescription)" }
    }

    private func removeTranslation(_ language: String) {
        do {
            try TakeLibrary.update(take) { $0.translations[language] = nil }
            translations[language] = nil
            shown = nil
            library.refresh()
        } catch { problem = "Could not remove the translation: \(error.localizedDescription)" }
    }

    private func saveCaptions(language: String) {
        guard let cues = translations[language] else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = CaptionTranslation.captionFileName(baseName: take.files.baseName, language: language)
        panel.allowedContentTypes = [UTType(filenameExtension: "vtt") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Captions.webVTT(cues).write(to: url, atomically: true, encoding: .utf8) }
        catch { problem = "Could not save the captions: \(error.localizedDescription)" }
    }

    private func beginEditing(_ index: Int) {
        guard segments.indices.contains(index), status == nil, !showingTranslation else { return }
        player.player.pause()  // so the words stay put while you type
        draft = segments[index].text
        savedNote = false
        problem = ""
        editingIndex = index
    }

    /// Ends the open line. Saved unless it was cancelled, left empty, or not changed.
    private func finishEditing(cancelled: Bool) {
        guard let index = editingIndex else { return }
        editingIndex = nil
        guard !cancelled, segments.indices.contains(index) else { return }
        var texts = segments.map(\.text)
        texts[index] = draft
        let updated = TranscriptEditing.apply(texts, to: segments)
        let cleaned = draft.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !cleaned.isEmpty, updated != segments else { return }
        do {
            try TakeLibrary.saveTranscript(updated, for: take)
            segments = updated
            // The saved translations were made from the old words and are dropped with them.
            translations = [:]
            shown = nil
            savedNote = true
            library.refresh()
            Task { try? await Task.sleep(for: .seconds(2)); savedNote = false }
        } catch { problem = "Could not save the transcript: \(error.localizedDescription)" }
    }

    private func make() {
        guard status == nil else { return }
        status = "Starting…"
        problem = ""
        Task {
            defer { status = nil }
            do {
                // Remaking replaces what is there; the first time simply makes it.
                if !segments.isEmpty { try? TakeLibrary.update(take) { $0.transcript = []; $0.translations = [:]; $0.words = [] } }
                translations = [:]
                shown = nil
                segments = try await Transcripts.ensure(for: take) { status = $0 }
                if segments.isEmpty { problem = "No speech was found in this recording." }
                library.refresh()
                chapters.findAutomatically { }
            } catch { problem = "Could not make the transcript: \(error.localizedDescription)" }
        }
    }
}

/// What the Edit menu's Find items do in the transcript on screen. Nil (items greyed out) when there is no transcript.
struct TranscriptFindActions {
    var show: () -> Void
    var next: () -> Void
    var previous: () -> Void
}

private struct TranscriptFindKey: FocusedValueKey { typealias Value = TranscriptFindActions }

extension FocusedValues {
    var transcriptFind: TranscriptFindActions? {
        get { self[TranscriptFindKey.self] }
        set { self[TranscriptFindKey.self] = newValue }
    }
}

/// Find in Transcript, Find Next and Find Previous in the Edit menu, with the usual shortcuts.
struct TranscriptFindCommands: Commands {
    @FocusedValue(\.transcriptFind) private var find

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Find in Transcript…") { find?.show() }.keyboardShortcut("f").disabled(find == nil)
            Button("Find Next") { find?.next() }.keyboardShortcut("g").disabled(find == nil)
            Button("Find Previous") { find?.previous() }.keyboardShortcut("g", modifiers: [.command, .shift]).disabled(find == nil)
        }
    }
}

/// A thin draggable bar between the video and a panel on its right. Dragging left widens the panel;
/// double-click puts it back to the default width.
struct PaneDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    let current: Double
    var reset = 380.0
    @State private var startWidth: Double?

    var body: some View {
        Rectangle().fill(.separator).frame(width: 1)
            .padding(.horizontal, 7)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let start = startWidth ?? current
                    startWidth = start
                    width = min(max(start - drag.translation.width, range.lowerBound), range.upperBound)
                }
                .onEnded { _ in startWidth = nil })
            .onTapGesture(count: 2) { width = reset }
            .accessibilityLabel("Resize transcript")
            .accessibilityAdjustableAction { direction in
                let step = 40.0
                width = min(max(current + (direction == .increment ? step : -step), range.lowerBound), range.upperBound)
            }
            .help("Drag to resize the video and transcript. Double-click to reset.")
    }
}
