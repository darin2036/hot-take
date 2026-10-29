import AppKit
import RelaytakeCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A take with its edit, in one file (`.hottake`). Declared in the app's Info.plist.
    static let hotTake = UTType(exportedAs: "org.relaytake.hottake", conformingTo: .data)
}

/// Opening and saving `.hottake` files: the whole take, with the Studio edit, in one file to hand to someone.
extension LibraryModel {
    /// Unpacks a file into the library as a new take (never replacing one) and shows it. Failures leave the
    /// library untouched and say why.
    func openPackage(_ url: URL) {
        let destination = recordingDirectory
        Task {
            do {
                let imported = try await Task.detached(priority: .userInitiated) {
                    try TakePackage.importPackage(from: url, into: destination)
                }.value
                select(files: imported.files)
                NotificationCenter.default.post(name: .relaytakeReopen, object: nil)
            } catch {
                self.error = error.localizedDescription
                NotificationCenter.default.post(name: .relaytakeReopen, object: nil)
            }
        }
    }

    /// File ▸ Open Hot Take File…
    func chooseAndOpenPackage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.hotTake]
        panel.allowsMultipleSelection = true
        panel.message = "Choose Hot Take files to add to your library."
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(openPackage)
    }
}

extension StudioModel {
    /// Saves the take and its current edit as one `.hottake` file the person picks a place for.
    /// `done` is told whether the project was saved (false when the panel was canceled or the save failed).
    func shareProject(then done: ((Bool) -> Void)? = nil) {
        guard ready, saveProgress == nil else { done?(false); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.hotTake]
        panel.nameFieldStringValue = take.title + "." + HotTakeFile.fileExtension
        panel.message = "Saves the recording and your Studio edit in one file. The person who opens it sees exactly what you see."
        panel.prompt = "Save Project"
        guard panel.runModal() == .OK, let destination = panel.url else { done?(false); return }

        saveDraftNow()
        let saved = project
        let draft = project.isEdited ? StudioDraft(project: project, playhead: time) : nil
        let files = take.files, title = take.title
        saveProgress = 0
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try TakePackage.export(files: files, title: title, draft: draft, to: destination) { value in
                        Task { @MainActor [weak self] in self?.saveProgress = value }
                    }
                }.value
                saveProgress = nil
                markProjectSaved(saved)
                info = "Saved \(destination.lastPathComponent). Anyone with Hot Take can open it."
                NSWorkspace.shared.activateFileViewerSelecting([destination])
                done?(true)
            } catch {
                saveProgress = nil
                message = error.localizedDescription
                done?(false)
            }
        }
    }
}
