import AVKit
import AppKit
import RelaytakeCore
import SwiftUI

struct LibraryView: View {
    @ObservedObject var library: LibraryModel
    @ObservedObject var recorder: RecorderModel
    @Environment(\.openSettings) private var openSettings
    /// Whether the folder list is open beside the recordings (which makes the window wider to fit it).
    @AppStorage("sidebarVisible") private var sidebarPinned = false
    @AppStorage("detailsShowInfo") private var showInfo = false
    @State private var detailTab: DetailTab = .watch
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var window: NSWindow?
    /// Set while the pinned state is being restored at launch, so that does not resize the window.
    @State private var restoring = true

    /// Width the pinned folder list takes (its default column width).
    private static let sidebarWidth: CGFloat = 220

    /// The smallest the page beside the folder list may be, for what is showing: the library, or a
    /// recording on its Watch, Transcript or Studio tab. Smaller and the toolbar or the page would clip.
    private var contentMinimum: CGSize {
        // Widths are set by the toolbar, which on a recording page holds the back button, the three tabs,
        // New Take, Share and Settings; narrower than this it folds them into a ">>" menu and hides the tabs.
        guard library.selected != nil else { return CGSize(width: 680, height: 440) }
        switch detailTab {
        case .watch: return CGSize(width: showInfo ? 840 : 800, height: 560)
        case .transcript: return CGSize(width: 800, height: 560)
        case .studio: return CGSize(width: 800, height: 580)
        }
    }

    private var pinned: Bool { columnVisibility != .detailOnly }

    /// Grows or shrinks the window by the folder list's width, keeping it on screen.
    private func resizeWindow(byWidth delta: CGFloat, minimumWidth: CGFloat) {
        guard let window else { return }
        var frame = window.frame
        frame.size.width = max(frame.size.width + delta, minimumWidth)
        if let visible = window.screen?.visibleFrame {
            frame.size.width = min(frame.size.width, visible.width)
            if frame.maxX > visible.maxX { frame.origin.x = max(visible.minX, visible.maxX - frame.width) }
        }
        // Not animated: the window's own resize animation is slow and runs on top of the list's, so the list felt late.
        window.setFrame(frame, display: true, animate: false)
    }

    /// When the page being shown needs more room than the window has, make the window big enough.
    private func ensureRoom() {
        guard let window else { return }
        let needed = CGSize(width: contentMinimum.width + (pinned ? Self.sidebarWidth : 0), height: contentMinimum.height)
        var frame = window.frame
        let content = window.contentLayoutRect.size
        let growWidth = max(0, needed.width - content.width), growHeight = max(0, needed.height - content.height)
        guard growWidth > 0 || growHeight > 0 else { return }
        frame.size.width += growWidth
        frame.size.height += growHeight
        frame.origin.y -= growHeight  // keep the top edge where it is
        if let visible = window.screen?.visibleFrame {
            frame.size.width = min(frame.size.width, visible.width)
            frame.size.height = min(frame.size.height, visible.height)
            if frame.maxX > visible.maxX { frame.origin.x = max(visible.minX, visible.maxX - frame.width) }
            if frame.minY < visible.minY { frame.origin.y = visible.minY }
        }
        window.setFrame(frame, display: true, animate: true)
    }

    /// The recordings the header buttons act on: the open one, or else the selection.
    private var targets: [TakeEntry] {
        if let open = library.selected { return [open] }
        return library.visibleTakes.filter { library.checked.contains($0.id) }
    }

    private func askToTrash() {
        if library.selected != nil { library.confirmDetailTrash = true } else { library.confirmBulkTrash = true }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(library: library)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            Group {
                if let take = library.selected {
                    TakeDetailView(take: take, library: library, tab: $detailTab).id(take.id)
                } else {
                    LibraryBrowser(library: library, recorder: recorder)
                }
            }
            .frame(minWidth: contentMinimum.width, minHeight: contentMinimum.height)
        }
        .background(WindowReader { if window !== $0 { window = $0 } })
        .background(TrashKeyHandler(
            enabled: !targets.isEmpty && library.prompt == nil && !library.confirmBulkTrash
                && !library.confirmDetailTrash && !recorder.choosing && !recorder.isBusy,
            action: askToTrash
        ))
        .onChange(of: library.selection) { _, _ in detailTab = .watch }
        .onAppear {
            columnVisibility = sidebarPinned ? .all : .detailOnly
            DispatchQueue.main.async { restoring = false }
        }
        .onChange(of: columnVisibility) { old, new in
            sidebarPinned = (new != .detailOnly)
            // Opening widens the window by the folder list, and unpinning gives the width back.
            if !restoring, (old == .detailOnly) != (new == .detailOnly) {
                let nowPinned = new != .detailOnly
                resizeWindow(
                    byWidth: nowPinned ? Self.sidebarWidth : -Self.sidebarWidth,
                    minimumWidth: contentMinimum.width + (nowPinned ? Self.sidebarWidth : 0))
            }
        }
        .onChange(of: contentMinimum) { _, _ in ensureRoom() }
        // Floats over the content instead of pushing it down, so nothing (such as the video) is cut off.
        .overlay(alignment: .bottom) { StatusBanner(recorder: recorder).padding(.bottom, 14).padding(.horizontal, 16) }
        .toolbar {
            if library.selected != nil {
                ToolbarItem(placement: .navigation) {
                    Button("Library", systemImage: "chevron.left") { library.selection = nil }
                        .help("Back to all recordings")
                }
            }
            // Actions for whatever is selected (or open): they appear only when there is something to act on.
            ToolbarItemGroup(placement: .primaryAction) {
                if library.selected == nil && !targets.isEmpty {
                    Button { askToTrash() } label: { Label("Trash", systemImage: "trash") }
                        .labelStyle(.titleAndIcon)
                        .help(targets.count == 1 ? "Move to Trash" : "Move \(targets.count) recordings to the Trash")
                }
            }
            if library.selected != nil {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Recording view", selection: $detailTab) {
                        ForEach(DetailTab.allCases) { section in
                            Label(section.rawValue, systemImage: section.symbol).tag(section)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .labelStyle(.titleAndIcon).fixedSize()
                }
            }
            ToolbarItem(placement: .primaryAction) { RecordButton(recorder: recorder) }
                .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) {
                if let studio = library.openStudio, detailTab == .studio, targets.count == 1 {
                    StudioShareButton(model: studio)
                } else {
                    ShareLink(items: targets.map(\.files.video)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(targets.isEmpty)
                    .help(targets.isEmpty ? "Select a recording to share" : "Share selected recordings")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Settings", systemImage: "gearshape") { openSettings() }
                    .help("Settings")
            }
        }
        .sheet(isPresented: $recorder.choosing) { SourceChooser(recorder: recorder) }
        .overlay { if let request = library.theater { TheaterView(request: request, library: library) } }
        .alert(library.promptTitle, isPresented: Binding(get: { library.prompt != nil }, set: { if !$0 { library.prompt = nil } })) {
            TextField("Name", text: $library.promptText)
            Button("Cancel", role: .cancel) {}
            Button(library.promptConfirm) { library.commitPrompt() }
        }
        .alert("Something went wrong", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK") { library.error = nil }
        } message: { Text(library.error ?? "") }
        .onAppear { library.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            library.refresh()
        }
    }
}

/// Where each card sits in the grid's own coordinate space, for box selection and arrow keys.
private struct CardFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// All recordings, selectable like files in a file manager. A list when the window is narrow; otherwise a
/// grid that adds columns as it widens.
private struct LibraryBrowser: View {
    @ObservedObject var library: LibraryModel
    @ObservedObject var recorder: RecorderModel

    /// Below this width, thumbnails would be cramped; use compact rows instead.
    private let listBreakpoint: CGFloat = 560

    @State private var frames: [String: CGRect] = [:]
    @State private var marquee: CGRect?
    @State private var marqueeBase: Set<String> = []
    @State private var marqueeAdditive = false
    @FocusState private var gridFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            Group {
                if library.visibleTakes.isEmpty {
                    emptyState
                } else if geometry.size.width < listBreakpoint {
                    list
                } else {
                    grid(minHeight: geometry.size.height)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .contextMenu { BackgroundMenu(library: library, recorder: recorder) }
        .navigationTitle(library.scopeTitle)
        .navigationSubtitle("\(library.matchingCount) recording\(library.matchingCount == 1 ? "" : "s")")
        .searchable(text: $library.query, placement: .toolbar, prompt: "Search recordings")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Like a file manager's status line; no buttons, the keyboard and right-click do the work.
            if !library.checked.isEmpty {
                Text("\(library.checked.count) of \(library.visibleTakes.count) selected")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(.bar)
            }
        }
        .confirmationDialog(
            "Move \(library.checked.count) recording\(library.checked.count == 1 ? "" : "s") to the Trash?",
            isPresented: $library.confirmBulkTrash, titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { library.trashChecked() }
        } message: {
            Text("Videos, captions and notes move to the Trash. You can restore them from there.")
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !library.query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: library.query)
        } else if case .folder = library.scope {
            ContentUnavailableView {
                Label("This folder is empty", systemImage: "folder")
                    .help("Drag recordings here from the library, or start a new take to record into this folder.")

            } actions: {
                RecordButton(recorder: recorder, prominent: true)
            }
        } else {
            ContentUnavailableView {
                Label("No recordings yet", systemImage: "record.circle")

            } actions: {
                RecordButton(recorder: recorder, prominent: true)
            }
        }
    }

    private func askToTrash() {
        if !library.checked.isEmpty { library.confirmBulkTrash = true }
    }

    // MARK: List (narrow): the native list gives click, ⌘-click, ⇧-click and arrow keys

    private var list: some View {
        List(selection: Binding(get: { library.checked }, set: { library.setSelection($0) })) {
            ForEach(library.visibleTakes) { take in
                TakeRow(take: take, library: library)
                    .tag(take.id)
                    .draggable(library.dragPayload(for: take.id))
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let first = ids.first, let take = library.takes.first(where: { $0.id == first }) {
                TakeActions(take: take, library: library)
            } else {
                BackgroundMenu(library: library, recorder: recorder)
            }
        } primaryAction: { ids in
            if ids.count == 1 { library.selection = ids.first }  // double-click
        }
        .onDeleteCommand { askToTrash() }
        .onKeyPress(.return) { library.openSelected(); return .handled }
        .onKeyPress(.escape) { library.clearSelection(); return .handled }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Grid (wide): click, ⌘/⇧-click, box select, arrows, drag

    private func grid(minHeight: CGFloat) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 16)], spacing: 16) {
                ForEach(library.visibleTakes) { take in
                    TakeCard(take: take, library: library, selected: library.checked.contains(take.id))
                        .background(GeometryReader { geometry in
                            Color.clear.preference(
                                key: CardFramesKey.self, value: [take.id: geometry.frame(in: .named("grid"))])
                        })
                        .onTapGesture(count: 2) {
                            library.click(take.id, command: false, shift: false)
                            library.selection = take.id
                        }
                        .onTapGesture {
                            let flags = NSEvent.modifierFlags
                            library.click(take.id, command: flags.contains(.command), shift: flags.contains(.shift))
                            gridFocused = true
                        }
                        .draggable(library.dragPayload(for: take.id))
                        .contextMenu { TakeActions(take: take, library: library) }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
            .background { emptySpace }
            .overlay(alignment: .topLeading) { marqueeView }
            .coordinateSpace(name: "grid")
        }
        .onPreferenceChange(CardFramesKey.self) { frames = $0 }
        .focusable()
        .focused($gridFocused)
        .focusEffectDisabled()
        .onAppear { gridFocused = true }
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Behind the cards: a click clears the selection, a drag draws a selection box.
    private var emptySpace: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                library.clearSelection()
                gridFocused = true
            }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("grid"))
                    .onChanged { value in
                        if marquee == nil {
                            let flags = NSEvent.modifierFlags
                            marqueeAdditive = flags.contains(.command) || flags.contains(.shift)
                            marqueeBase = library.checked
                            gridFocused = true
                        }
                        let rect = CGRect(
                            x: min(value.startLocation.x, value.location.x),
                            y: min(value.startLocation.y, value.location.y),
                            width: abs(value.location.x - value.startLocation.x),
                            height: abs(value.location.y - value.startLocation.y))
                        marquee = rect
                        let hits = Set(frames.filter { $0.value.intersects(rect) }.keys)
                        library.boxSelect(hits: hits, base: marqueeBase, additive: marqueeAdditive)
                    }
                    .onEnded { _ in marquee = nil }
            )
    }

    @ViewBuilder private var marqueeView: some View {
        if let rect = marquee {
            Rectangle()
                .fill(Color.accentColor.opacity(0.15))
                .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }

    /// Cards in the first row = columns, for up/down arrows.
    private var columns: Int {
        guard let top = frames.values.map(\.minY).min() else { return 1 }
        return max(1, frames.values.filter { abs($0.minY - top) < 2 }.count)
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let extend = press.modifiers.contains(.shift)
        switch press.key {
        case .leftArrow: library.moveSelection(by: -1, extend: extend)
        case .rightArrow: library.moveSelection(by: 1, extend: extend)
        case .upArrow: library.moveSelection(by: -columns, extend: extend)
        case .downArrow: library.moveSelection(by: columns, extend: extend)
        case .escape: library.clearSelection()
        case .return: library.openSelected()
        case .delete, .deleteForward: askToTrash()
        default:
            if press.characters.lowercased() == "a", press.modifiers.contains(.command) {
                library.checkAllVisible()
            } else {
                return .ignored
            }
        }
        return .handled
    }
}

/// The folders a recording can be moved to, indented like the sidebar.
private struct MoveToMenu: View {
    @ObservedObject var library: LibraryModel
    /// Folder the recording is already in; that entry is disabled.
    var current: String?
    let pick: (String) -> Void

    var body: some View {
        Button("Top Level") { pick("") }.disabled(current == "")
        if !library.flatFolders.isEmpty { Divider() }
        ForEach(library.flatFolders, id: \.path) { folder in
            Button(String(repeating: "   ", count: folder.depth) + folder.name) { pick(folder.path) }
                .disabled(folder.path == current)
        }
    }
}

/// Right-click on a recording. If several are checked and this is one of them, it acts on all.
private struct TakeActions: View {
    let take: TakeEntry
    @ObservedObject var library: LibraryModel

    var body: some View {
        if library.checked.contains(take.id), library.checked.count > 1 {
            Text("\(library.checked.count) recordings selected")
            Menu("Move to", systemImage: "folder") {
                MoveToMenu(library: library, current: nil) { library.moveChecked(to: $0) }
            }
            Divider()
            Button("Move \(library.checked.count) to Trash…", systemImage: "trash", role: .destructive) {
                library.confirmBulkTrash = true
            }
        } else {
            Button("Open", systemImage: "play.rectangle") { library.selection = take.id }
            Button("Rename…", systemImage: "pencil") { library.ask(.renameTake(id: take.id)) }
            Divider()
            Menu("Move to", systemImage: "folder") {
                MoveToMenu(library: library, current: take.folder) { library.move(ids: [take.id], to: $0) }
            }
            Divider()
            Button("Show in Folder", systemImage: "magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting([take.files.video])
            }
            Button("Copy File Path", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(take.files.video.path, forType: .string)
            }
            Divider()
            Button("Move to Trash", systemImage: "trash", role: .destructive) { library.trashTake(take) }
        }
    }
}

/// Right-click on empty space in the library.
private struct BackgroundMenu: View {
    @ObservedObject var library: LibraryModel
    @ObservedObject var recorder: RecorderModel

    var body: some View {
        Button("New Take", systemImage: "record.circle") { recorder.toggle() }
        Button("New Folder…", systemImage: "folder.badge.plus") {
            library.ask(.newFolder(parent: library.currentFolderPath))
        }
        Divider()
        Button("Select All", systemImage: "checkmark.circle") { library.checkAllVisible() }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(library.visibleTakes.isEmpty)
        Divider()
        Button("Show in Folder", systemImage: "magnifyingglass") { library.showInFinder() }
        Button("Refresh", systemImage: "arrow.clockwise") { library.refresh() }
    }
}

private struct TakeCard: View {
    let take: TakeEntry
    @ObservedObject var library: LibraryModel
    var selected = false
    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        let versions = library.versionCount(of: take)
        let isVersion = library.isVersion(take)
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Rectangle().fill(.quaternary)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        if let image { Image(nsImage: image).resizable().scaledToFill() }
                    }
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        if versions > 0 {
                            // An original with saved versions: the pill opens or folds them away.
                            Button { withAnimation(.snappy(duration: 0.25)) { library.toggleVersions(of: take) } } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.stack.3d.up.fill")
                                    Text("\(versions) version\(versions == 1 ? "" : "s")")
                                    Image(systemName: library.isExpanded(take) ? "chevron.up" : "chevron.down").font(.caption2.weight(.bold))
                                }
                                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.black.opacity(0.7), in: Capsule())
                            }
                            .buttonStyle(.plain).padding(6)
                            .help(library.isExpanded(take) ? "Hide the versions saved from this recording" : "Show the versions saved from this recording")
                        } else if isVersion {
                            Label("Version", systemImage: "arrow.turn.down.right")
                                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.9), in: Capsule()).padding(6)
                        }
                    }
                if let seconds = library.durations[take.id] {
                    Text(timeLabel(seconds))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(take.title).font(.headline).lineLimit(2)
                if isVersion, let original = library.originalTitle(of: take) {
                    Text("Edited from \(original)").font(.caption).foregroundStyle(.tint).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(take.created.formatted(date: .abbreviated, time: .shortened))
                    if take.hasCaptions { Image(systemName: "captions.bubble").help("Has captions") }
                }
                .font(.caption).foregroundStyle(.secondary)
                if !take.summary.isEmpty {
                    Text(take.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                if !take.tags.isEmpty {
                    Text(take.tags.prefix(3).map { "#" + $0.replacingOccurrences(of: " ", with: "-") }.joined(separator: "  "))
                        .font(.caption).foregroundStyle(.tint).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(selected ? Color.accentColor.opacity(0.22) : (isVersion ? Color.accentColor.opacity(hovering ? 0.16 : 0.09) : Color.secondary.opacity(hovering ? 0.2 : 0.1)), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor, lineWidth: 3)
                .opacity(selected ? 1 : 0))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering = $0 }
        .task(id: take.id) {
            image = await library.thumbnail(for: take)
            _ = await library.duration(of: take)
        }
    }
}

private struct TakeRow: View {
    let take: TakeEntry
    @ObservedObject var library: LibraryModel
    @State private var image: NSImage?

    var body: some View {
        let versions = library.versionCount(of: take)
        let isVersion = library.isVersion(take)
        HStack(spacing: 10) {
            // A version is indented under its original.
            if isVersion {
                Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary).padding(.leading, 6)
            }
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 80, height: 45).clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(take.title).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if versions > 0 {
                Button { withAnimation(.snappy(duration: 0.25)) { library.toggleVersions(of: take) } } label: {
                    HStack(spacing: 3) {
                        Text("\(versions)")
                        Image(systemName: library.isExpanded(take) ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                }
                .buttonStyle(.plain)
                .help(library.isExpanded(take) ? "Hide the versions saved from this recording" : "Show the \(versions) version\(versions == 1 ? "" : "s") saved from this recording")
            }
        }
        .padding(.vertical, 2)
        .task(id: take.id) {
            image = await library.thumbnail(for: take)
            _ = await library.duration(of: take)
        }
    }

    private var subtitle: String {
        var parts = [take.created.formatted(date: .abbreviated, time: .shortened)]
        if let seconds = library.durations[take.id] { parts.append(timeLabel(seconds)) }
        if take.hasCaptions { parts.append("CC") }
        return parts.joined(separator: " · ")
    }
}

enum DetailTab: String, CaseIterable, Identifiable {
    case watch = "Watch"
    case transcript = "Transcript"
    case studio = "Studio"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .watch: "play.rectangle"
        case .transcript: "text.alignleft"
        case .studio: "slider.horizontal.3"
        }
    }
}

struct TakeDetailView: View {
    let take: TakeEntry
    @ObservedObject var library: LibraryModel
    @StateObject private var player = PlayerModel()

    @Binding var tab: DetailTab
    @State private var title = ""
    @State private var message = ""
    /// The info panel beside the video; remembered between recordings.
    @AppStorage("detailsShowInfo") private var showInfo = false
    @State private var summaryExpanded = false

    private var metadata: TakeMetadata? { TakeLibrary.metadata(for: take.files) }

    var body: some View {
        Group {
            if tab == .studio {
                // The Studio fills the pane and never scrolls: preview, timeline and tools all fit.
                StudioView(take: take, library: library, close: { tab = .watch })
            } else if tab == .transcript {
                TranscriptView(take: take, library: library, player: player)
            } else {
                VStack(spacing: 12) {
                    header
                    HStack(alignment: .top, spacing: 0) {
                        // The video and summary give way when the info panel slides in beside them.
                        VStack(spacing: 12) {
                            PlayerView(player: player.player, fileURL: take.files.video)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.black).clipped().layoutPriority(-1)
                                .playbackControls(title: take.title, owner: player, library: library) {
                                    AnyView(PlayerView(player: player.player, fileURL: take.files.video))
                                }
                            details
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if showInfo {
                            Divider().padding(.horizontal, 14)
                            InfoView(take: take, library: library)
                                .frame(width: 330)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .animation(.snappy(duration: 0.28), value: showInfo)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        .frame(minWidth: 600, minHeight: 560)
        .task { title = take.title; await player.load(take.files.video) }
        .onDisappear {
            PlayerWindows.shared.closeAll(ownedBy: player)
            library.theater = nil
        }
        .onChange(of: take.title) { _, new in title = new }
        .onChange(of: tab) { _, new in
            if new == .studio { player.player.pause() }  // the Studio plays its own edited copy
        }
        .confirmationDialog("Move this recording to the Trash?", isPresented: $library.confirmDetailTrash, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                do { try library.trash(take) } catch { message = error.localizedDescription }
            }
        } message: {
            Text("The video, captions and notes move to the Trash. You can restore them from there.")
        }
    }

    private var header: some View {
        let titleBlock = VStack(alignment: .leading, spacing: 2) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain).font(.title2.bold())
                .onSubmit { commitTitle() }
            Text(take.created.formatted(date: .complete, time: .shortened))
                .font(.caption).foregroundStyle(.secondary)
        }
        let actions = HStack {
            Button { showInfo.toggle() } label: {
                Label("Info", systemImage: "sidebar.right").symbolVariant(showInfo ? .fill : .none)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(showInfo ? "Hide the info panel (⌥⌘I)" : "Show the info panel: title, tags, summary, notes and file details (⌥⌘I)")
            Button("Trash", systemImage: "trash", role: .destructive) { library.confirmDetailTrash = true }
        }
        // Wide: title and buttons on one line. Narrow: buttons drop below the title.
        return ViewThatFits(in: .horizontal) {
            HStack { titleBlock; Spacer(); actions }
            VStack(alignment: .leading, spacing: 8) { titleBlock; actions }
        }
    }

    /// The summary takes the room it needs (up to a point, then scrolls), so there is no paging and no
    /// empty space beneath it.
    private var details: some View {
        let summary = metadata?.summary ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Summary").font(.headline)
                Spacer()
                if !summary.isEmpty {
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary, forType: .string)
                    }
                    .buttonStyle(.borderless).controlSize(.small).help("Copy the summary")
                }
            }
            // Natural height, so there is no empty space under it. A long summary shows its first lines, and
            // "Show more" opens the rest in place.
            Text(summary.isEmpty ? "No summary yet. Open Info and choose Generate." : summary)
                .foregroundStyle(summary.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .lineLimit(summaryExpanded ? nil : 8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            if summary.count > 450 {
                Button(summaryExpanded ? "Show less" : "Show more") { summaryExpanded.toggle() }
                    .buttonStyle(.link).font(.callout)
            }
        }
    }

    private func commitTitle() {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != take.title else { title = take.title; return }
        do { try TakeLibrary.rename(take, to: clean); library.refresh() } catch { message = error.localizedDescription }
    }
}

/// Red capsule drawn explicitly: the system strips most button styling inside toolbars.
struct TakeButtonStyle: ButtonStyle {
    var color: Color = .red
    var large = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .title3.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 22 : 14)
            .padding(.vertical, large ? 10 : 5)
            .background(Capsule().fill((enabled ? color : .gray).opacity(configuration.isPressed ? 0.75 : 1)))
            .contentShape(Capsule())
    }
}

/// "New Take" when idle, a live "Stop" with elapsed time while recording.
private struct RecordButton: View {
    @ObservedObject var recorder: RecorderModel
    var prominent = false

    var body: some View {
        switch recorder.phase {
        case .idle:
            Button { recorder.toggle() } label: { Label("New Take", systemImage: "record.circle.fill") }
                .buttonStyle(TakeButtonStyle(large: prominent))
                .keyboardShortcut("n")
                .help("Record your screen (⌘N)")
        case .recording(let since):
            Button { recorder.toggle() } label: {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Label("Stop  \(timeLabel(context.date.timeIntervalSince(since)))", systemImage: "stop.circle.fill")
                        .monospacedDigit()
                }
            }
            .buttonStyle(TakeButtonStyle(large: prominent))
            .keyboardShortcut("n")
            .help("Stop recording (⌘N)")
        case .saving, .processing:
            Button {} label: { Label("Working…", systemImage: "hourglass") }
                .buttonStyle(TakeButtonStyle(large: prominent))
                .disabled(true)
        }
    }
}

/// Progress after a recording and any error from recording or post-processing. A floating capsule at
/// the bottom of the window: it wraps to show the whole message and fades away on its own after a while.
private struct StatusBanner: View {
    @ObservedObject var recorder: RecorderModel

    var body: some View {
        let working: String? = switch recorder.phase {
        case .saving: "Saving…"
        case .processing(let text): text
        default: nil
        }
        if let working {
            capsule {
                ProgressView().controlSize(.small)
                Text(working).fixedSize(horizontal: false, vertical: true)
            }
        } else if !recorder.message.isEmpty {
            let message = recorder.message
            capsule {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(message).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Button("Dismiss") { recorder.message = "" }.buttonStyle(.link)
            }
            // Keyed to the text, so a new message gets its full time on screen.
            .task(id: message) {
                try? await Task.sleep(for: .seconds(12))
                if recorder.message == message { recorder.message = "" }
            }
        }
    }

    private func capsule<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) { content() }
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.separator))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

/// AVPlayerView that offers a right-click menu. AVPlayerView swallows right-clicks, so SwiftUI's
/// `.contextMenu` never sees them on the video.
final class MenuPlayerView: AVPlayerView {
    var fileURL: URL?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let fileURL else { return super.menu(for: event) }
        let menu = NSMenu()
        let reveal = NSMenuItem(title: "Show in Folder", action: #selector(reveal), keyEquivalent: "")
        reveal.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        let copy = NSMenuItem(title: "Copy File Path", action: #selector(copyPath), keyEquivalent: "")
        copy.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        for item in [reveal, copy] { item.target = self; menu.addItem(item) }
        return menu
    }

    @objc private func reveal() { if let fileURL { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) } }
    @objc private func copyPath() {
        guard let fileURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fileURL.path, forType: .string)
    }
}

/// AppKit's AVPlayerView. SwiftUI's VideoPlayer (_AVKit_SwiftUI) aborts at launch on the 27 release.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    /// The file being shown; gives the video a right-click menu with Show in Folder.
    var fileURL: URL?

    func makeNSView(context: Context) -> MenuPlayerView {
        let view = MenuPlayerView()
        view.player = player
        view.fileURL = fileURL
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ view: MenuPlayerView, context: Context) {
        if view.player !== player { view.player = player }
        view.fileURL = fileURL
    }
}


/// Hands back the window a view is in, so the library can resize it.
struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onChange(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onChange(view.window) }
    }
}
