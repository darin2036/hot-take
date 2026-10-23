import AppKit
import SwiftUI

/// Delete acts on recordings unless a text editor or modal sheet owns the keystroke.
struct TrashKeyHandler: NSViewRepresentable {
    var enabled: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> KeyView { KeyView() }
    func updateNSView(_ view: KeyView, context: Context) {
        view.enabled = enabled
        view.action = action
    }
    static func dismantleNSView(_ view: KeyView, coordinator: ()) { view.stop() }

    final class KeyView: NSView {
        var enabled = false
        var action: (() -> Void)?
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.enabled, let window = self.window,
                      event.window === window, window.isKeyWindow, window.attachedSheet == nil,
                      event.keyCode == 51 || event.keyCode == 117,
                      !event.isARepeat,
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                      !(window.firstResponder is NSTextView), !(window.firstResponder is NSTextField)
                else { return event }
                self.action?()
                return nil
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
