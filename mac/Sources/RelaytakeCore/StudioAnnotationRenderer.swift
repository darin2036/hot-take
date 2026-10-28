import AppKit
import CoreImage
import Foundation

/// The arrows, boxes, blurs and click rings for one export or preview. Everything that never changes from frame
/// to frame (the drawn arrows and boxes, the ring picture) is drawn once; a frame only fades, places and
/// blurs them. Marks are in the recorded picture's own coordinates, so they follow the window into a backdrop
/// and are magnified by a zoom, because the compositor draws them before the zoom is applied.
struct AnnotationLayer: @unchecked Sendable {
    private enum Prepared {
        case blur(shape: ShapeOverlay, rect: CGRect, sigma: Double)
        case drawn(shape: ShapeOverlay, image: CIImage)
    }

    private let prepared: [Prepared]
    private let timeline: ClickHighlightTimeline?
    private let ring: CIImage?
    private let ringDiameter: CGFloat
    private let canvas: CGSize
    private let content: CGRect

    /// Nil when there is nothing to draw.
    init?(canvas: CGSize, content: CGRect, shapes: [ShapeOverlay], highlight: ClickHighlight?, cuts: EditModel?) {
        let timeline = highlight.flatMap { highlight in cuts.map { ClickHighlightTimeline(highlight: highlight, cuts: $0) } }
        guard !shapes.isEmpty || timeline != nil, canvas.width > 0, canvas.height > 0, content.width > 0, content.height > 0
        else { return nil }
        self.canvas = canvas
        self.content = content
        self.timeline = timeline
        let shorter = Double(min(content.width, content.height))
        let space = Self.pixel(canvas: canvas, content: content)

        // Blurs go first, so an arrow or box over a blurred name is not itself blurred.
        var blurs: [Prepared] = []
        var drawn: [Prepared] = []
        for shape in shapes {
            let a = space(shape.x1, shape.y1), b = space(shape.x2, shape.y2)
            switch shape.kind {
            case .blur:
                let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
                blurs.append(.blur(shape: shape, rect: rect, sigma: max(1, shape.blurRadius * shorter)))
            case .box, .arrow:
                if let image = Self.draw(shape, from: a, to: b, shorter: shorter, aspect: Double(content.width / content.height), space: space) {
                    drawn.append(.drawn(shape: shape, image: image))
                }
            }
        }
        prepared = blurs + drawn

        if let highlight = timeline?.highlight {
            let diameter = max(8, CGFloat(highlight.size * shorter * 2))
            ringDiameter = diameter
            ring = Self.drawRing(diameter: diameter, color: highlight.color)
        } else {
            ringDiameter = 0
            ring = nil
        }
    }

    /// Maps a point in the recorded picture (0...1 from the top-left) to pixels, from the bottom-left as Core
    /// Image counts them.
    private static func pixel(canvas: CGSize, content: CGRect) -> (Double, Double) -> CGPoint {
        { x, y in CGPoint(x: content.minX + x * content.width, y: canvas.height - (content.minY + y * content.height)) }
    }

    /// Lays the marks over `image` (the picture, with its origin at the bottom-left) for one moment.
    func draw(over image: CIImage, at time: Double) -> CIImage {
        var result = image
        for item in prepared {
            switch item {
            case .blur(let shape, let rect, let sigma):
                let opacity = shape.opacity(at: time)
                guard opacity > 0.001, rect.width > 1, rect.height > 1 else { continue }
                let blurred = result.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: rect)
                result = Self.faded(blurred, opacity).composited(over: result)
            case .drawn(let shape, let picture):
                let opacity = shape.opacity(at: time)
                guard opacity > 0.001 else { continue }
                result = Self.faded(picture, opacity).composited(over: result)
            }
        }
        if let timeline, let ring {
            let space = Self.pixel(canvas: canvas, content: content)
            for item in timeline.rings(at: time) {
                let center = space(item.x, item.y)
                let scale = CGFloat(item.scale)
                let placed = ring
                    .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    .transformed(by: CGAffineTransform(translationX: center.x - ringDiameter * scale / 2, y: center.y - ringDiameter * scale / 2))
                result = Self.faded(placed, item.opacity).composited(over: result)
            }
        }
        return result.cropped(to: CGRect(origin: .zero, size: canvas))
    }

    private static func faded(_ image: CIImage, _ opacity: Double) -> CIImage {
        opacity >= 0.999
            ? image
            : image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity))])
    }

    private static func cgColor(_ color: TextColor, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: alpha)
    }

    /// An arrow or box drawn into a picture just big enough to hold it, positioned where it belongs.
    private static func draw(
        _ shape: ShapeOverlay, from a: CGPoint, to b: CGPoint, shorter: Double, aspect: Double,
        space: (Double, Double) -> CGPoint
    ) -> CIImage? {
        let width = max(2, CGFloat(shape.lineWidth * shorter))
        let pad = ceil(width * 4 + 8)
        let bounds = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            .insetBy(dx: -pad, dy: -pad).integral
        guard bounds.width >= 1, bounds.height >= 1, bounds.width < 16_000, bounds.height < 16_000,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.setShadow(offset: CGSize(width: 0, height: -width * 0.35), blur: width * 0.8, color: CGColor(gray: 0, alpha: 0.4))
        context.setStrokeColor(cgColor(shape.color))
        context.setFillColor(cgColor(shape.color))
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch shape.kind {
        case .box:
            let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            context.addPath(CGPath(roundedRect: rect, cornerWidth: min(width * 1.5, rect.width / 2), cornerHeight: min(width * 1.5, rect.height / 2), transform: nil))
            context.strokePath()
        case .arrow:
            // The geometry works in picture fractions; bring its points through the same mapping as the ends.
            let geometry = ArrowGeometry(
                from: CGPoint(x: shape.x1, y: shape.y1), to: CGPoint(x: shape.x2, y: shape.y2),
                lineWidth: shape.lineWidth, aspect: aspect)
            func at(_ p: CGPoint) -> CGPoint { space(p.x, p.y) }
            context.move(to: a)
            context.addLine(to: at(geometry.shaftEnd))
            context.strokePath()
            context.move(to: b)
            context.addLine(to: at(geometry.wingA))
            context.addLine(to: at(geometry.wingB))
            context.closePath()
            context.drawPath(using: .fillStroke)
        case .blur:
            return nil
        }
        guard let image = context.makeImage() else { return nil }
        return CIImage(cgImage: image).transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
    }

    private static func drawRing(diameter: CGFloat, color: TextColor) -> CIImage? {
        let side = Int(ceil(diameter))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let stroke = max(2, diameter * 0.08)
        let rect = CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)).insetBy(dx: stroke / 2, dy: stroke / 2)
        context.setFillColor(cgColor(color, alpha: 0.22))
        context.fillEllipse(in: rect)
        context.setStrokeColor(cgColor(color, alpha: 0.95))
        context.setLineWidth(stroke)
        context.strokeEllipse(in: rect)
        return context.makeImage().map { CIImage(cgImage: $0) }
    }
}
