import AppKit
import RelaytakeCore
import SwiftUI

/// Edit by text: the take's transcript beside the Studio preview. Choose lines and cut them, and the video they were
/// spoken over goes with them; lines already cut are struck through and can be brought back. Every change is one
/// undoable step on the same cut list as the timeline.
struct StudioTranscriptPanel: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var clock: StudioClock

    private var chosen: [Int] { model.selectedLines.sorted() }
    private var canCut: Bool { chosen.contains { model.lineState($0) != .cut } }
    private var canRestore: Bool { chosen.contains { model.lineState($0) != .kept } }

    /// The line under the playhead, found from the moment of the original that is playing.
    private var playing: Int? {
        model.project.cuts.sourceTime(forOutput: clock.time).flatMap { TranscriptCuts.line(at: $0, in: model.transcriptLines) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript").font(.headline)
                Spacer()
                if !model.selectedLines.isEmpty {
                    Text("\(model.selectedLines.count) selected").font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.transcriptLines.isEmpty { empty } else {
                Text("Select lines, then press Delete to cut them from the video. Shift-click picks a run of lines.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                list
                HStack {
                    Button { model.cutLines(model.selectedLines) } label: { Label("Cut Lines", systemImage: "scissors") }
                        .disabled(!canCut)
                        .help("Cut the selected lines and the video under them (Delete). You can undo it.")
                    Button { model.restoreLines(model.selectedLines) } label: { Label("Bring Back", systemImage: "arrow.uturn.backward") }
                        .disabled(!canRestore)
                        .help("Put the cut parts of the selected lines back where they were")
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { model.loadTranscript() }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.alignleft").font(.system(size: 26)).foregroundStyle(.secondary)
            Text("No transcript yet.").foregroundStyle(.secondary)
            Button("Make Transcript") { model.makeTranscript() }.disabled(model.transcriptStatus != nil)
                .help("Listens to the recording on this Mac. Nothing leaves your Mac.")
            if let status = model.transcriptStatus {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(status).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.transcriptLines.enumerated()), id: \.offset) { item in
                        row(item.offset, item.element)
                    }
                }
            }
            .onChange(of: playing) { _, new in
                if let new, model.isPlaying { withAnimation { proxy.scrollTo(new, anchor: .center) } }
            }
        }
    }

    private func row(_ index: Int, _ line: CaptionSegment) -> some View {
        let state = model.lineState(index)
        let picked = model.selectedLines.contains(index)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(timeLabel(line.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(line.text)
                    .strikethrough(state == .cut)
                    .foregroundStyle(state == .cut ? .secondary : .primary)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                if state == .partlyCut { Text("Partly cut").font(.caption2).foregroundStyle(.orange) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(
            picked ? Color.accentColor.opacity(0.3) : playing == index ? Color.accentColor.opacity(0.12) : .clear,
            in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            model.clickLine(index, shift: flags.contains(.shift), command: flags.contains(.command))
        }
        .contextMenu {
            let targets = picked ? model.selectedLines : [index]
            Button("Cut", systemImage: "scissors") { model.cutLines(targets) }
                .disabled(!targets.contains { model.lineState($0) != .cut })
            Button("Bring Back", systemImage: "arrow.uturn.backward") { model.restoreLines(targets) }
                .disabled(!targets.contains { model.lineState($0) != .kept })
        }
        .help(state == .cut ? "Cut from the video. Select it and choose Bring Back to put it back." : "Click to jump here. Shift-click or Command-click to select more.")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(state == .cut ? "Cut" : state == .partlyCut ? "Partly cut" : "")
        .accessibilityAction(named: "Cut this line") { model.cutLines([index]) }
        .accessibilityAction(named: "Bring back this line") { model.restoreLines([index]) }
    }
}
