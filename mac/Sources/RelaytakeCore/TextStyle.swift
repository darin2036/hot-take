import AppKit
import Foundation

public extension TextOverlay {
    /// Fonts offered in the Studio: the system font first, then familiar families, but only the ones
    /// this Mac actually has.
    static var fontFamilies: [String] {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        let candidates = [
            "Helvetica Neue", "Avenir Next", "Futura", "Gill Sans", "Optima", "Georgia", "Times New Roman",
            "American Typewriter", "Menlo", "Marker Felt", "Chalkboard SE", "Impact",
        ]
        return [systemFont] + candidates.filter(installed.contains)
    }

    /// The font for this text at `pointSize`. The saved video and the Studio's preview both use this, so
    /// what you see is what you get.
    func nsFont(pointSize: CGFloat) -> NSFont {
        let fallback = NSFont.systemFont(ofSize: pointSize, weight: isBold ? .bold : .regular)
        var font = fallback
        if fontFamily != Self.systemFont {
            var traits: NSFontTraitMask = []
            if isBold { traits.insert(.boldFontMask) }
            font = NSFontManager.shared.font(withFamily: fontFamily, traits: traits, weight: isBold ? 9 : 5, size: pointSize) ?? fallback
        }
        if isItalic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }
}

public extension TextColor {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    init(_ color: NSColor) {
        let converted = color.usingColorSpace(.sRGB) ?? color
        self.init(red: converted.redComponent, green: converted.greenComponent, blue: converted.blueComponent)
    }
}
