import AppKit
import RelaytakeCore
import SwiftUI

/// The menu bar, laid out the way Mac apps usually are: File (new, open, import, save, export, reveal), Edit (the
/// system's, plus Find in Transcript), View, Record, Take, Studio, Window and Help. Every item is also reachable
/// from the window; the menus only gather them in the expected places and add the shortcuts.

/// The recordings a menu item acts on: the one open, else the ones checked in the library.
@MainActor private func menuTargets(_ library: LibraryModel) -> [TakeEntry] {
    if let open = library.selected { return [open] }
    return library.visibleTakes.filter { library.checked.contains($0.id) }
}

@MainActor private func showLibraryWindow(_ open: OpenWindowAction) {
    NSApplication.shared.activate(ignoringOtherApps: true)
    open(id: "library")
}

// MARK: File

struct FileCommands: Commands {
    @ObservedObject var recorder: RecorderModel
    @ObservedObject private var library = LibraryModel.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(recorder.isRecording ? "Stop Recording" : "New Take") { recorder.toggle() }
                .keyboardShortcut("n")
                .disabled(recorder.isBusy)
            Button("New Folder…") { library.ask(.newFolder(parent: library.currentFolderPath)) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Open Hot Take File…") { library.chooseAndOpenPackage() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(library.takes.prefix(8)) { take in
                    Button(take.title) {
                        library.selection = take.id
                        showLibraryWindow(openWindow)
                    }
                }
            }
            .disabled(library.takes.isEmpty)
            Button("Import Video…") { library.chooseAndImportVideos() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        CommandGroup(after: .saveItem) {
            Button("Save Copy") {
                guard let studio = library.openStudio else { return }
                let options = StudioSaveOptions.stored
                if studio.canSave(options) { studio.save(options: options) {} }
                else { studio.message = "Make an edit, or choose a smaller file size in Save Options, first." }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(library.openStudio == nil)
            Button("Save Project…") { library.openStudio?.shareProject() }
                .keyboardShortcut("s")
                .disabled(library.openStudio == nil)
            Menu("Export") {
                ForEach(VideoExportFormat.allCases) { format in
                    Button("\(format.rawValue.uppercased()) Video…") {
                        library.exportVideo(format: format)
                    }
                    .disabled(library.exportTake == nil || !format.available)
                }
                Divider()
                Button("Transcript as Markdown…") { library.exportTranscriptMarkdown() }
                    .disabled(library.exportTake == nil)
            }
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(menuTargets(library).map(\.files.video))
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(menuTargets(library).isEmpty)
            Button("Show Library Folder") { recorder.openFolder() }
            Divider()
        }
    }
}

// MARK: Record

struct RecordCommands: Commands {
    @ObservedObject var recorder: RecorderModel

    var body: some Commands {
        CommandMenu("Record") {
            Button(recorder.isRecording ? "Stop Recording" : "New Take…") { recorder.toggle() }
                .disabled(recorder.isBusy)
            Button(recorder.paused ? "Resume" : "Pause") { recorder.paused ? recorder.resume() : recorder.pause() }
                .disabled(!recorder.isRecording || !recorder.canPause)
            Button("Rewind 10 Seconds") { recorder.rewind() }
                .disabled(!recorder.canRewind)
            Button("Restart Take") { recorder.restart() }
                .disabled(!recorder.isRecording)
            Divider()
            Button("Quick Record") { recorder.quickRecord() }
                .disabled(recorder.phase != .idle)
            Button("Quick Take for Agent") { recorder.quickRecordForAgent() }
                .disabled(recorder.phase != .idle)
            Button("Take Screenshot") { recorder.quickScreenshot() }
                .disabled(recorder.phase != .idle)
            Divider()
            Button("Speaker Notes") { SpeakerNotesWindow.shared.toggle() }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }
    }
}

// MARK: Take

struct TakeCommands: Commands {
    @ObservedObject var recorder: RecorderModel
    @ObservedObject private var library = LibraryModel.shared

    var body: some Commands {
        let targets = menuTargets(library)
        let one = targets.count == 1 ? targets.first : nil
        CommandMenu("Take") {
            Button("Open") { if let one { library.selection = one.id } }
                .disabled(one == nil || library.selected != nil)
            Button("Rename…") { if let one { library.ask(.renameTake(id: one.id)) } }
                .disabled(one == nil)
            Button("Join Recordings") { recorder.join(targets) }
                .disabled(targets.count < 2)
            Divider()
            Button("Copy for Agent") { if let one { recorder.copyForAgent(one) } }
                .disabled(one == nil)
            Button("Copy Bug Report") { if let one { recorder.copyBugReport(one) } }
                .disabled(one == nil)
            Divider()
            Button("Copy File Path") {
                if let one {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(one.files.video.path, forType: .string)
                }
            }
            .disabled(one == nil)
            Divider()
            Button("Move to Trash…") {
                if library.selected != nil { library.confirmDetailTrash = true } else { library.confirmBulkTrash = true }
            }
            .disabled(targets.isEmpty)
        }
    }
}

// MARK: Studio

/// The Studio's editing actions, on while a Studio is open.
struct StudioCommands: Commands {
    @ObservedObject private var library = LibraryModel.shared

    var body: some Commands {
        CommandMenu("Studio") {
            let studio = library.openStudio
            Group {
                Button("Play / Pause") { studio?.togglePlay() }
                Divider()
                Button("Splice at Playhead") { studio?.splice() }
                    .keyboardShortcut("b")
                Button("Add Text") { studio?.addText() }
                Button("Add Music…") { studio?.chooseMusic() }
                Button("Add Zoom at Playhead") { studio?.addZoom() }
                Divider()
                Button("Remove Selection") { studio?.deleteSelection() }
            }
            .disabled(studio == nil)
        }
    }
}

// MARK: View

struct ViewCommands: Commands {
    @ObservedObject private var library = LibraryModel.shared
    @AppStorage("detailsShowInfo") private var showInfo = false

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Back to Library") { library.selection = nil }
                .keyboardShortcut("[")
                .disabled(library.selected == nil)
            Button(showInfo ? "Hide Info Panel" : "Show Info Panel") { showInfo.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(library.selected == nil)
            Button("Refresh Library") { library.refresh() }
                .keyboardShortcut("r")
            Divider()
        }
    }
}
