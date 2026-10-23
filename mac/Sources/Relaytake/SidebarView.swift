import AppKit
import RelaytakeCore
import SwiftUI

/// Optional left navigation: all recordings plus a real folder tree. Drag takes onto a folder to
/// move them. Hide it with the standard sidebar button in the toolbar.
struct SidebarView: View {
    @ObservedObject var library: LibraryModel

    @State private var folderToTrash: FolderNode?
    @State private var allTargeted = false

    private var scopeBinding: Binding<LibraryScope?> {
        Binding(get: { library.scope }, set: { if let value = $0 { library.show(value) } })
    }

    var body: some View {
        List(selection: scopeBinding) {
            Label("All Recordings", systemImage: "square.grid.2x2")
                .badge(library.count(in: .all))
                .tag(LibraryScope.all)
                .padding(.vertical, 1)
                .background(allTargeted ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
                // Dropping on All Recordings takes items out of their folder, back to the top level.
                .dropDestination(for: String.self) { payloads, _ in
                    library.drop(payloads, into: "")
                    return true
                } isTargeted: { allTargeted = $0 }
                .contextMenu {
                    Button("New Folder…", systemImage: "folder.badge.plus") { library.ask(.newFolder(parent: "")) }
                    Button("Show in Folder", systemImage: "magnifyingglass") {
                        NSWorkspace.shared.open(library.directory)
                    }
                }

            Section("Folders") {
                OutlineGroup(library.folders, children: \.childrenOrNil) { node in
                    FolderRow(node: node, library: library, onTrash: { folderToTrash = node })
                        .tag(LibraryScope.folder(node.path))
                }
                if library.folders.isEmpty {
                    Text("No folders yet").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            // Right-click on empty space in the sidebar.
            Button("New Folder…", systemImage: "folder.badge.plus") { library.ask(.newFolder(parent: "")) }
            Button("Show Library Folder", systemImage: "magnifyingglass") { NSWorkspace.shared.open(library.directory) }
            Button("Refresh", systemImage: "arrow.clockwise") { library.refresh() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { library.ask(.newFolder(parent: "")) } label: {
                Label("New Folder", systemImage: "folder.badge.plus").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.bar)
        }
        .confirmationDialog(
            "Move “\(folderToTrash?.title ?? "")” to the Trash?",
            isPresented: Binding(get: { folderToTrash != nil }, set: { if !$0 { folderToTrash = nil } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let node = folderToTrash { library.trashFolder(node.path) }
                folderToTrash = nil
            }
        } message: {
            Text("The folder and every recording in it move to the Trash. You can restore them from there.")
        }
    }
}

private struct FolderRow: View {
    let node: FolderNode
    @ObservedObject var library: LibraryModel
    let onTrash: () -> Void
    @State private var targeted = false
    @State private var choosingIcon = false

    var body: some View {
        Label {
            Text(node.title)
        } icon: {
            if let icon = node.icon { Text(icon) } else { Image(systemName: "folder") }
        }
            .badge(library.count(in: .folder(node.path)))
            .padding(.vertical, 1)
            .background(targeted ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .dropDestination(for: String.self) { payloads, _ in
                library.drop(payloads, into: node.path)
                return true
            } isTargeted: { targeted = $0 }
            .popover(isPresented: $choosingIcon, arrowEdge: .trailing) {
                FolderIconPicker(current: node.icon) { icon in
                    choosingIcon = false
                    library.setFolderIcon(node.path, to: icon)
                }
            }
            .contextMenu {
                Button("New Subfolder…", systemImage: "folder.badge.plus") { library.ask(.newFolder(parent: node.path)) }
                Button("Rename…", systemImage: "pencil") { library.ask(.renameFolder(path: node.path)) }
                Button("Choose Icon…", systemImage: "face.smiling") { choosingIcon = true }
                Button("Show in Folder", systemImage: "magnifyingglass") {
                    if let url = try? TakeLibrary.resolve(node.path, in: library.directory) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Divider()
                Button("Move to Trash…", systemImage: "trash", role: .destructive) { onTrash() }
            }
    }
}

/// Pick an emoji for a folder: a grid of common ones, or type or paste any emoji.
private struct FolderIconPicker: View {
    let current: String?
    let choose: (String?) -> Void
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Folder icon").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 6), spacing: 4) {
                ForEach(FolderName.suggestions, id: \.self) { emoji in
                    Button { choose(emoji) } label: {
                        Text(emoji).font(.system(size: 22)).frame(width: 34, height: 34)
                            .background(current == emoji ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).accessibilityLabel(emoji)
                }
            }
            HStack {
                TextField("Any emoji", text: $typed)
                    .textFieldStyle(.roundedBorder).frame(width: 100)
                    .onSubmit { if let emoji = FolderName.leadingEmoji(in: typed) { choose(emoji) } }
                    .help("Type or paste an emoji and press Return. Press Control-Command-Space for the emoji picker.")
                Spacer()
                Button("No Icon") { choose(nil) }.disabled(current == nil)
            }
        }
        .padding(14).frame(width: 250)
    }
}
