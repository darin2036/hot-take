import AppKit
import RelaytakeCore
import SwiftUI

/// The words of a recording next to its video. Click a line to play from there; the line being spoken
/// is highlighted and followed as the video plays.
struct TranscriptView: View {
    let take: TakeEntry
    @ObservedObject var library: LibraryModel
    @ObservedObject var player: PlayerModel

    @State private var segments: [CaptionSegment] = []
    @State private var loaded = false
    @State private var query = ""
    @State private var status: String?
    @State private var problem = ""
    /// The line being corrected, and what it says so far. Double-click a line to start; Return or clicking away saves.
    @State private var editingIndex: Int?
    @State private var draft = ""
    @State private var confirmRemake = false
    @State private var savedNote = false

    private var shown: [(offset: Int, segment: CaptionSegment)] {
        let all = Array(segments.enumerated()).map { (offset: $0.offset, segment: $0.element) }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? all : all.filter { $0.segment.text.localizedCaseInsensitiveContains(term) }
    }

    private var activeIndex: Int? {
        segments.lastIndex { $0.start <= player.time + 0.05 && player.time < $0.end + 0.05 }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PlayerView(player: player.player, fileURL: take.files.video)
                .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
                .background(.black).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 10) {
                header
                if segments.isEmpty { empty } else { list }
            }
            .frame(width: 380, alignment: .topLeading).frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(16)
        .task(id: take.id) { editingIndex = nil; reload() }
        .confirmationDialog("Remake the transcript?", isPresented: $confirmRemake) {
            Button("Remake", role: .destructive) { make() }
        } message: {
            Text("This listens again and replaces the current text, including any corrections you made.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript").font(.title3.bold())
                Spacer()
                if !segments.isEmpty {
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(segments.map(\.text).joined(separator: "\n"), forType: .string)
                    }.help("Copy the whole transcript")
                    Button(role: .none) { confirmRemake = true } label: { Label("Remake", systemImage: "arrow.clockwise") }
                        .disabled(status != nil)
                        .help("Listen to the recording again on this Mac and replace the transcript")
                }
            }
            if savedNote {
                Label("Saved", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            } else if !segments.isEmpty, editingIndex == nil {
                Text("Double-click a line to correct it.").font(.caption).foregroundStyle(.secondary)
            }
            if !segments.isEmpty {
                TextField("Search the transcript", text: $query).textFieldStyle(.roundedBorder)
            }
            if let status {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            if !problem.isEmpty { Text(problem).font(.caption).foregroundStyle(.red) }
        }
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
                    ForEach(shown, id: \.offset) { item in
                        let active = activeIndex == item.offset
                        if editingIndex == item.offset {
                            HStack(alignment: .top, spacing: 10) {
                                Text(timeLabel(item.segment.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).padding(.top, 5)
                                // Return saves, Escape puts the old words back, and clicking anywhere else saves.
                                LineEditor(text: $draft) { cancelled in finishEditing(cancelled: cancelled) }
                                    .accessibilityLabel("Transcript line at \(timeLabel(item.segment.start))")
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3).id(item.offset)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(timeLabel(item.segment.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                Text(item.segment.text).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(active ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            // One click plays from the line; the second click of a double-click opens it for correcting.
                            .onTapGesture {
                                if NSApp.currentEvent?.clickCount == 2 { beginEditing(item.offset) } else { player.play(from: item.segment.start) }
                            }
                            .help("Click to play from here. Double-click to correct the words.")
                            .id(item.offset)
                            .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction(named: "Correct this line") { beginEditing(item.offset) }
                        }
                    }
                    if shown.isEmpty { Text("Nothing matches.").foregroundStyle(.secondary).padding(8) }
                }
            }
            .onChange(of: activeIndex) { _, new in
                if let new, query.isEmpty, editingIndex == nil { withAnimation { proxy.scrollTo(new, anchor: .center) } }
            }
        }
    }

    private func reload() {
        segments = TakeLibrary.metadata(for: take.files)?.transcript ?? []
        loaded = true
    }

    private func beginEditing(_ index: Int) {
        guard segments.indices.contains(index), status == nil else { return }
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
                if !segments.isEmpty { try? TakeLibrary.update(take) { $0.transcript = [] } }
                segments = try await Transcripts.ensure(for: take) { status = $0 }
                if segments.isEmpty { problem = "No speech was found in this recording." }
                library.refresh()
            } catch { problem = "Could not make the transcript: \(error.localizedDescription)" }
        }
    }
}

/// A text field for correcting one transcript line. It takes the keyboard as soon as it appears. Return finishes,
/// Escape cancels, and a click anywhere outside it finishes too: a click on plain text or empty space does not move
/// keyboard focus by itself in a SwiftUI window, so the click is watched for directly.
private struct LineEditor: NSViewRepresentable {
    @Binding var text: String
    /// Called once, when editing ends. `cancelled` is true for Escape.
    let onDone: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.cornerRadius = 5
        field.layer?.borderWidth = 1.5
        field.layer?.borderColor = NSColor.controlAccentColor.cgColor
        field.font = .preferredFont(forTextStyle: .body)
        field.lineBreakMode = .byWordWrapping
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.delegate = context.coordinator
        context.coordinator.field = field
        context.coordinator.takeKeyboard()
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
    }

    /// Wraps to the width it is given and grows as the line gets longer.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: NSTextField, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let size = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(24, (size?.height ?? 24) + 6))
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LineEditor
        weak var field: NSTextField?
        private var monitor: Any?
        private var cancelled = false
        private var finished = false

        init(_ parent: LineEditor) { self.parent = parent }
        deinit { stopWatching() }

        /// Takes the keyboard once the field is in its window, trying again for a moment if the window is not ready.
        func takeKeyboard(attempt: Int = 0) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let field = self.field, !self.finished else { return }
                guard let window = field.window else {
                    if attempt < 20 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.takeKeyboard(attempt: attempt + 1) } }
                    return
                }
                window.makeFirstResponder(field)
                (field.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: (field.stringValue as NSString).length, length: 0))
                self.watchClicks()
            }
        }

        func watchClicks() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let field = self.field, let window = field.window, event.window === window else { return event }
                let point = field.convert(event.locationInWindow, from: nil)
                if !field.bounds.contains(point) { window.makeFirstResponder(nil) }  // ends editing, which saves
                return event
            }
        }

        private func stopWatching() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        func controlTextDidChange(_ notification: Notification) {
            if let field { parent.text = field.stringValue }
            field?.invalidateIntrinsicContentSize()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                control.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                cancelled = true
                control.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard !finished else { return }
            finished = true
            stopWatching()
            if !cancelled, let field { parent.text = field.stringValue }
            let wasCancelled = cancelled
            let done = parent.onDone
            DispatchQueue.main.async { done(wasCancelled) }
        }
    }
}
