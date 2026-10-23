import AppKit
import AVKit
import SwiftUI

/// What the theater overlay is showing. The content is built by whoever asked, so the same modes work
/// for a plain recording and for the Studio's edited preview (which draws its text on top).
struct TheaterRequest: Identifiable {
    let id = UUID()
    let title: String
    let content: () -> AnyView
}

/// Pop-out and full-screen windows. A window is tied to the thing that opened it (a take's player,
/// or a Studio), so it closes when you leave that screen instead of lingering with a stopped video.
@MainActor
final class PlayerWindows: NSObject, NSWindowDelegate {
    static let shared = PlayerWindows()

    private struct Entry {
        let window: NSWindow
        weak var owner: AnyObject?
        let closesWhenLeavingFullScreen: Bool
    }

    private var entries: [Entry] = []

    /// A resizable window that stays above the others, like picture-in-picture.
    @discardableResult
    func popOut(owner: AnyObject, title: String, aspect: CGSize?, content: AnyView) -> NSWindow {
        let width: CGFloat = 640
        let size = aspect.map { CGSize(width: width, height: width * $0.height / max($0.width, 1)) } ?? CGSize(width: width, height: 380)
        let window = makeWindow(title: title, size: size, content: content)
        window.level = .floating
        if let aspect, aspect.width > 0 { window.contentAspectRatio = aspect }
        window.minSize = CGSize(width: 320, height: 200)
        window.center()
        register(window, owner: owner, closesWhenLeavingFullScreen: false)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    /// Straight into full screen. Leaving full screen (Esc) closes the window again.
    @discardableResult
    func fullScreen(owner: AnyObject, title: String, content: AnyView, enterNow: Bool = true) -> NSWindow {
        let window = makeWindow(title: title, size: CGSize(width: 960, height: 540), content: content)
        window.collectionBehavior = [.fullScreenPrimary]
        window.center()
        register(window, owner: owner, closesWhenLeavingFullScreen: true)
        window.makeKeyAndOrderFront(nil)
        if enterNow { window.toggleFullScreen(nil) }
        return window
    }

    var openCount: Int { entries.count }

    func closeAll(ownedBy owner: AnyObject) {
        for entry in entries where entry.owner === owner { entry.window.close() }
    }

    private func makeWindow(title: String, size: CGSize, content: AnyView) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.contentView = NSHostingView(rootView: content.background(Color.black).environment(\.colorScheme, .dark))
        window.delegate = self
        return window
    }

    private func register(_ window: NSWindow, owner: AnyObject, closesWhenLeavingFullScreen: Bool) {
        entries.append(Entry(window: window, owner: owner, closesWhenLeavingFullScreen: closesWhenLeavingFullScreen))
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.contentView = nil  // stop the hosted player view
        entries.removeAll { $0.window === window }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              entries.first(where: { $0.window === window })?.closesWhenLeavingFullScreen == true
        else { return }
        window.close()
    }
}

/// The three playback modes as a small bar that appears over the video when the pointer is on it.
struct PlaybackButtons: View {
    let title: String
    let owner: AnyObject
    @ObservedObject var library: LibraryModel
    var aspect: CGSize?
    let content: () -> AnyView

    var body: some View {
        HStack(spacing: 2) {
            button("rectangle.expand.vertical", "Theater mode: fill the window (⌥⌘T)") {
                library.theater = TheaterRequest(title: title, content: content)
            }
            .keyboardShortcut("t", modifiers: [.option, .command])

            button("pip.enter", "Pop out into its own window (⌥⌘P)") {
                PlayerWindows.shared.popOut(owner: owner, title: title, aspect: aspect, content: content())
            }
            .keyboardShortcut("p", modifiers: [.option, .command])

            button("arrow.up.left.and.arrow.down.right", "Full screen (⌥⌘F)") {
                PlayerWindows.shared.fullScreen(owner: owner, title: title, content: content())
            }
            .keyboardShortcut("f", modifiers: [.option, .command])
        }
        .padding(4)
        .background(.black.opacity(0.6), in: Capsule())
        .foregroundStyle(.white)
    }

    private func button(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

extension View {
    /// Adds theater, pop-out and full-screen buttons to the corner of a video, shown on hover.
    func playbackControls(
        title: String, owner: AnyObject, library: LibraryModel, aspect: CGSize? = nil, content: @escaping () -> AnyView
    ) -> some View {
        modifier(PlaybackControlsModifier(title: title, owner: owner, library: library, aspect: aspect, content: content))
    }
}

private struct PlaybackControlsModifier: ViewModifier {
    let title: String
    let owner: AnyObject
    @ObservedObject var library: LibraryModel
    let aspect: CGSize?
    let content: () -> AnyView
    @State private var hovering = false

    func body(content view: Content) -> some View {
        view
            .overlay(alignment: .topTrailing) {
                PlaybackButtons(title: title, owner: owner, library: library, aspect: aspect, content: content)
                    .padding(10)
                    .opacity(hovering ? 1 : 0)  // always in the view tree so the shortcuts keep working
                    .animation(.easeOut(duration: 0.15), value: hovering)
            }
            .onHover { hovering = $0 }
    }
}

/// Fills the whole window with the video; Esc or the close button goes back.
struct TheaterView: View {
    let request: TheaterRequest
    @ObservedObject var library: LibraryModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            request.content()
            Button { library.theater = nil } label: {
                Label("Exit Theater", systemImage: "xmark")
                    .labelStyle(.titleAndIcon)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)  // Esc
            .help("Back to the window (Esc)")
            .padding(12)
        }
    }
}
