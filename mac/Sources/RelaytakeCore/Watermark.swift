import AppKit
import CoreImage
import Foundation

// An optional mark (a logo, a name, or both) drawn in one corner of every saved video, for demos and for
// people who want their own branding. It is drawn into the picture when a video is saved and in the Studio's
// preview, never into the raw recording. The geometry here is pure and tested.

public enum WatermarkCorner: String, CaseIterable, Codable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    public var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
}

public struct Watermark: @unchecked Sendable {
    public static let sizeRange = 0.03...0.15
    public static let opacityRange = 0.2...1.0
    public static let defaultSize = 0.06
    public static let defaultOpacity = 0.9

    public var logo: CGImage?
    public var text: String
    public var corner: WatermarkCorner
    /// Height of the mark as a fraction of the video's height, so it looks the same at any resolution.
    public var size: Double
    public var opacity: Double

    public init(
        logo: CGImage? = nil, text: String = "", corner: WatermarkCorner = .topLeft,
        size: Double = Watermark.defaultSize, opacity: Double = Watermark.defaultOpacity
    ) {
        self.logo = logo
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.corner = corner
        self.size = min(Self.sizeRange.upperBound, max(Self.sizeRange.lowerBound, size))
        self.opacity = min(Self.opacityRange.upperBound, max(Self.opacityRange.lowerBound, opacity))
    }

    /// Nothing to draw: no logo and no words.
    public var isEmpty: Bool { logo == nil && text.isEmpty }
}

public enum WatermarkLayout {
    /// Where a mark of `size` sits in the picture (pixels, from the top-left), `margin` in from the chosen corner.
    public static func origin(canvas: CGSize, size: CGSize, corner: WatermarkCorner, margin: CGFloat) -> CGPoint {
        CGPoint(
            x: corner.isLeft ? margin : max(0, canvas.width - size.width - margin),
            y: corner.isTop ? margin : max(0, canvas.height - size.height - margin))
    }
}

public enum WatermarkRenderer {
    /// Draws the mark once, already placed, ready to be laid over every frame. Nil when there is nothing to draw.
    public static func render(_ watermark: Watermark, renderSize: CGSize) -> CIImage? {
        guard !watermark.isEmpty, renderSize.width > 0, renderSize.height > 0 else { return nil }
        let height = max(8, (renderSize.height * watermark.size).rounded())
        let margin = (height * 0.5).rounded()
        let gap = height * 0.3

        var textSize = CGSize.zero
        var attributes: [NSAttributedString.Key: Any] = [:]
        if !watermark.text.isEmpty {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
            shadow.shadowBlurRadius = height * 0.08
            shadow.shadowOffset = CGSize(width: 0, height: -height * 0.03)
            attributes = [
                .font: NSFont.systemFont(ofSize: height * 0.55, weight: .semibold),
                .foregroundColor: NSColor.white, .shadow: shadow,
            ]
            let measured = (watermark.text as NSString).size(withAttributes: attributes)
            // Never wider than half the picture, so a long name cannot cover it.
            textSize = CGSize(width: min(ceil(measured.width), renderSize.width * 0.5), height: ceil(measured.height))
        }
        let pad = height * 0.12  // room for the shadows
        let logoWidth = watermark.logo == nil ? 0 : height
        let contentWidth = logoWidth + (logoWidth > 0 && textSize.width > 0 ? gap : 0) + textSize.width
        let size = CGSize(width: ceil(contentWidth + pad * 2), height: ceil(height + pad * 2))

        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setAlpha(watermark.opacity)
        var x = pad
        if let logo = watermark.logo {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -height * 0.03), blur: height * 0.08, color: CGColor(gray: 0, alpha: 0.5))
            context.interpolationQuality = .high
            context.draw(logo, in: CGRect(x: x, y: pad, width: height, height: height))
            context.restoreGState()
            x += height + gap
        }
        if !watermark.text.isEmpty {
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            (watermark.text as NSString).draw(
                with: CGRect(x: x, y: pad + (height - textSize.height) / 2, width: textSize.width, height: textSize.height),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let image = context.makeImage() else { return nil }

        // The layout measures from the top-left; Core Image from the bottom-left. The padding stays inside the margin.
        let top = WatermarkLayout.origin(canvas: renderSize, size: size, corner: watermark.corner, margin: margin - pad)
        return CIImage(cgImage: image).transformed(
            by: CGAffineTransform(translationX: top.x, y: renderSize.height - top.y - size.height))
    }
}
