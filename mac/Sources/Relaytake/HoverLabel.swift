import SwiftUI

/// A small name that appears beside an icon-only control a moment after the pointer rests on it. The system's own
/// tooltip is slower and shows the long description, so this gives the name first.
private struct HoverLabel: ViewModifier {
    let text: String?
    let above: Bool
    let anchor: HorizontalAlignment
    @State private var hovering = false
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hovering = inside
                guard text != nil else { return }
                if inside {
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        if hovering { withAnimation(.easeOut(duration: 0.1)) { shown = true } }
                    }
                } else {
                    shown = false
                }
            }
            .overlay(alignment: Alignment(horizontal: anchor, vertical: above ? .top : .bottom)) {
                if shown, let text {
                    Text(text)
                        .font(.caption).foregroundStyle(.primary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.separator))
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                        .fixedSize()
                        .offset(y: above ? -30 : 30)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .zIndex(shown ? 10 : 0)
    }
}

extension View {
    /// Shows `text` near the control while the pointer rests on it. Nil shows nothing (for when the control already
    /// carries its name on screen). `above: false` puts it underneath, for controls at the top of a window.
    func hoverLabel(_ text: String?, above: Bool = true, anchor: HorizontalAlignment = .center) -> some View {
        modifier(HoverLabel(text: text, above: above, anchor: anchor))
    }
}
