import AVFoundation
import AppKit
import CoreImage
import Foundation

/// A text overlay drawn once, ready to be laid over each frame it is visible in.
struct RenderedOverlay: @unchecked Sendable {
    let overlay: TextOverlay
    let image: CIImage  // already positioned (Core Image's origin is the bottom-left)
}

/// Draws a text overlay to an image. The look (size as a fraction of the picture's height, a rounded
/// dark box, center position measured from the top-left) matches the Studio's preview.
enum TextRenderer {
    static func render(_ overlay: TextOverlay, renderSize: CGSize) -> RenderedOverlay? {
        let text = overlay.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, renderSize.width > 0, renderSize.height > 0 else { return nil }

        let fontSize = renderSize.height * overlay.heightFraction
        let font = overlay.nsFont(pointSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .paragraphStyle: paragraph, .foregroundColor: overlay.color.nsColor,
        ]
        if !overlay.showsBackground {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
            shadow.shadowBlurRadius = fontSize * 0.12
            shadow.shadowOffset = .zero
            attributes[.shadow] = shadow
        }

        let maxWidth = renderSize.width * 0.8
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
        let padding = overlay.showsBackground ? fontSize * 0.4 : fontSize * 0.2
        let size = CGSize(width: ceil(measured.width) + padding * 2, height: ceil(measured.height) + padding * 1.2)

        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        if overlay.showsBackground {
            overlay.boxColor.nsColor.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: fontSize * 0.35, yRadius: fontSize * 0.35).fill()
        }
        (text as NSString).draw(
            with: CGRect(x: padding, y: padding * 0.6, width: size.width - padding * 2, height: ceil(measured.height)),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        guard let cgImage = context.makeImage() else { return nil }

        // The model measures from the top-left; Core Image from the bottom-left.
        let origin = CGPoint(
            x: min(max(0, overlay.x * renderSize.width - size.width / 2), max(0, renderSize.width - size.width)),
            y: min(max(0, (1 - overlay.y) * renderSize.height - size.height / 2), max(0, renderSize.height - size.height)))
        return RenderedOverlay(
            overlay: overlay, image: CIImage(cgImage: cgImage).transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y)))
    }
}

/// The backdrop, rounded window and zoom for one export or preview, with the parts that never change
/// from frame to frame (the backdrop with its shadow, and the window's rounded-corner mask) drawn once.
struct CanvasEffects: @unchecked Sendable {
    let canvas: CGSize
    let content: CGRect  // pixels from the top-left; the whole canvas when there is no background
    let backdrop: CIImage?
    let mask: CIImage?
    let zooms: [ZoomSegment]
    /// Arrows, boxes, blurs and click rings, drawn on the recorded picture before any zoom.
    let annotations: AnnotationLayer?

    init(
        canvas: CGSize, source: CGSize, background: WindowBackground?, zooms: [ZoomSegment],
        shapes: [ShapeOverlay] = [], clickHighlight: ClickHighlight? = nil, cuts: EditModel? = nil
    ) {
        self.canvas = canvas
        self.zooms = zooms
        content = CanvasLayout.contentRect(canvas: canvas, source: source, background: background)
        annotations = AnnotationLayer(canvas: canvas, content: content, shapes: shapes, highlight: clickHighlight, cuts: cuts)
        if let background, let layers = Self.layers(canvas: canvas, content: content, background: background) {
            backdrop = layers.backdrop
            mask = layers.mask
        } else {
            backdrop = nil
            mask = nil
        }
    }

    private static func layers(canvas: CGSize, content: CGRect, background: WindowBackground) -> (backdrop: CIImage, mask: CIImage)? {
        let width = Int(canvas.width), height = Int(canvas.height)
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        func context() -> CGContext? {
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let back = context(), let cut = context() else { return nil }
        // Core Graphics measures from the bottom-left; the layout from the top-left.
        let rect = CGRect(x: content.minX, y: canvas.height - content.maxY, width: content.width, height: content.height)
        let radius = background.cornerRadius * min(content.width, content.height)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        func cgColor(_ color: TextColor) -> CGColor { CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1) }
        if background.isSolid {
            back.setFillColor(cgColor(background.top))
            back.fill(CGRect(origin: .zero, size: canvas))
        } else if let gradient = CGGradient(
            colorsSpace: space, colors: [cgColor(background.top), cgColor(background.bottom)] as CFArray, locations: [0, 1]) {
            back.drawLinearGradient(
                gradient, start: CGPoint(x: 0, y: canvas.height), end: CGPoint(x: canvas.width, y: 0), options: [])
        }
        if background.shadow {
            back.saveGState()
            let shorter = min(canvas.width, canvas.height)
            back.setShadow(offset: CGSize(width: 0, height: -shorter * 0.014), blur: shorter * 0.045, color: CGColor(gray: 0, alpha: 0.5))
            back.setFillColor(CGColor(gray: 0, alpha: 1))
            back.addPath(path)
            back.fillPath()
            back.restoreGState()
        }

        cut.setFillColor(CGColor(gray: 0, alpha: 1))
        cut.fill(CGRect(origin: .zero, size: canvas))
        cut.setFillColor(CGColor(gray: 1, alpha: 1))
        cut.addPath(path)
        cut.fillPath()
        guard let backImage = back.makeImage(), let cutImage = cut.makeImage() else { return nil }
        return (CIImage(cgImage: backImage), CIImage(cgImage: cutImage))
    }

    /// The picture for one frame: the window set into the backdrop, then zoomed toward where it is looking.
    func compose(_ frame: CIImage, at time: Double) -> CIImage {
        var image = frame
        let bounds = CGRect(origin: .zero, size: canvas)
        if let backdrop, let mask {
            let scale = content.width / max(1, frame.extent.width)
            let placed = frame
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: content.minX, y: canvas.height - content.maxY))
            image = placed.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: backdrop, kCIInputMaskImageKey: mask])
                .cropped(to: bounds)
        }
        if let annotations { image = annotations.draw(over: image, at: time) }
        let state = ZoomCamera.state(at: time, zooms: zooms)
        if state.zoom > 1.0001 {
            let focus = CanvasLayout.canvasPoint(forSource: state.focusX, state.focusY, content: content, canvas: canvas)
            let crop = ZoomCamera.crop(zoom: state.zoom, focusX: focus.x, focusY: focus.y)
            let rect = CGRect(
                x: crop.minX * canvas.width, y: (1 - crop.maxY) * canvas.height,
                width: crop.width * canvas.width, height: crop.height * canvas.height)
            image = image.clampedToExtent().cropped(to: rect)
                .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
                .transformed(by: CGAffineTransform(scaleX: state.zoom, y: state.zoom))
                .cropped(to: bounds)
        }
        return image
    }
}

/// The camera bubble for one export or preview: where it sits and its shape, with the shadow and border
/// drawn once, and the code that fits each camera frame into it.
struct CameraEffect: @unchecked Sendable {
    let trackID: CMPersistentTrackID
    let transform: CGAffineTransform
    let canvas: CGSize
    let bubble: CameraBubble
    let frame: CGRect  // pixels from the top-left of the picture
    /// The stretches of the edited video (seconds) where the camera has footage. Outside them the bubble is
    /// not drawn, because a composition holds a track's last frame after it ends.
    let intervals: [ClosedRange<Double>]
    private let mask: CIImage
    private let shadow: CIImage
    private let ring: CIImage?

    init(
        trackID: CMPersistentTrackID, transform: CGAffineTransform, canvas: CGSize, bubble: CameraBubble,
        intervals: [ClosedRange<Double>]
    ) {
        self.intervals = intervals
        self.trackID = trackID
        self.transform = transform
        self.canvas = canvas
        self.bubble = bubble
        frame = bubble.frame(in: canvas)
        let side = max(2, Int(frame.width.rounded()))
        let pad = max(8, Int(frame.width * 0.12))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!

        func path(in rect: CGRect) -> CGPath {
            bubble.shape == .circle
                ? CGPath(ellipseIn: rect, transform: nil)
                : CGPath(roundedRect: rect, cornerWidth: rect.width * 0.22, cornerHeight: rect.width * 0.22, transform: nil)
        }
        func context(_ size: Int) -> CGContext? {
            CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        let blankMask = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        if let maskContext = context(side) {
            maskContext.setFillColor(CGColor(gray: 0, alpha: 1))
            maskContext.fill(CGRect(x: 0, y: 0, width: side, height: side))
            maskContext.setFillColor(CGColor(gray: 1, alpha: 1))
            maskContext.addPath(path(in: CGRect(x: 0, y: 0, width: side, height: side)))
            maskContext.fillPath()
            mask = maskContext.makeImage().map { CIImage(cgImage: $0) } ?? blankMask
        } else {
            mask = blankMask
        }
        let full = side + pad * 2
        if let shadowContext = context(full) {
            shadowContext.setShadow(offset: CGSize(width: 0, height: -Double(side) * 0.03), blur: Double(side) * 0.07, color: CGColor(gray: 0, alpha: 0.45))
            shadowContext.setFillColor(CGColor(gray: 0, alpha: 1))
            shadowContext.addPath(path(in: CGRect(x: pad, y: pad, width: side, height: side)))
            shadowContext.fillPath()
            shadow = shadowContext.makeImage().map { CIImage(cgImage: $0) } ?? CIImage.empty()
        } else {
            shadow = CIImage.empty()
        }
        if bubble.hasBorder, let ringContext = context(full) {
            let width = max(2, Double(side) * 0.025)
            ringContext.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
            ringContext.setLineWidth(width)
            ringContext.addPath(path(in: CGRect(x: Double(pad) + width / 2, y: Double(pad) + width / 2, width: Double(side) - width, height: Double(side) - width)))
            ringContext.strokePath()
            ring = ringContext.makeImage().map { CIImage(cgImage: $0) }
        } else {
            ring = nil
        }
        self.pad = pad
    }

    private let pad: Int

    func isShowing(at time: Double) -> Bool { intervals.contains { $0.contains(time) } }

    /// Draws one camera frame into its bubble over `image` (the picture, with its origin at the bottom-left).
    func draw(_ pixels: CVPixelBuffer, over image: CIImage) -> CIImage {
        var camera = CIImage(cvPixelBuffer: pixels)
        if !transform.isIdentity {
            camera = camera.transformed(by: transform)
            camera = camera.transformed(by: CGAffineTransform(translationX: -camera.extent.minX, y: -camera.extent.minY))
        }
        let side = frame.width
        let cover = side / max(1, min(camera.extent.width, camera.extent.height))
        camera = camera.transformed(by: CGAffineTransform(scaleX: cover, y: cover))
        // Keep the middle square, so a wide camera picture is not squashed.
        camera = camera.cropped(to: CGRect(
            x: (camera.extent.width - side) / 2, y: (camera.extent.height - side) / 2, width: side, height: side))
        camera = camera.transformed(by: CGAffineTransform(translationX: -camera.extent.minX, y: -camera.extent.minY))
        if bubble.isMirrored {
            camera = camera.transformed(by: CGAffineTransform(scaleX: -1, y: 1)).transformed(by: CGAffineTransform(translationX: side, y: 0))
        }
        let origin = CGPoint(x: frame.minX, y: canvas.height - frame.maxY)
        let place = CGAffineTransform(translationX: origin.x, y: origin.y)
        let padding = CGFloat(pad)
        var result = shadow.transformed(by: CGAffineTransform(translationX: origin.x - padding, y: origin.y - padding)).composited(over: image)
        result = camera.transformed(by: place)
            .applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: result, kCIInputMaskImageKey: mask.transformed(by: place)])
        if let ring { result = ring.transformed(by: CGAffineTransform(translationX: origin.x - padding, y: origin.y - padding)).composited(over: result) }
        return result.cropped(to: CGRect(origin: .zero, size: canvas))
    }
}

final class StudioInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true  // the text fades, so frames differ over time
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let transform: CGAffineTransform
    let overlays: [RenderedOverlay]
    let effects: CanvasEffects?
    let camera: CameraEffect?

    init(
        timeRange: CMTimeRange, trackID: CMPersistentTrackID, transform: CGAffineTransform, overlays: [RenderedOverlay],
        effects: CanvasEffects? = nil, camera: CameraEffect? = nil
    ) {
        self.effects = effects
        self.camera = camera
        self.timeRange = timeRange
        self.trackID = trackID
        self.transform = transform
        self.overlays = overlays
        requiredSourceTrackIDs = [NSNumber(value: trackID)] + (camera.map { [NSNumber(value: $0.trackID)] } ?? [])
    }
}

/// Lays the pre-drawn text over each frame, fading it in and out.
final class StudioCompositor: NSObject, AVVideoCompositing {
    private static let context = CIContext()
    private let attributes: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    private let queue = DispatchQueue(label: "relaytake.studio.compositor")
    /// The last picture drawn on, kept to hold when the video runs out. Only touched on `queue`.
    private var lastFrame: CVPixelBuffer?

    var sourcePixelBufferAttributes: [String: any Sendable]? { attributes }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { attributes }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async {
            guard let instruction = request.videoCompositionInstruction as? StudioInstruction,
                  let output = request.renderContext.newPixelBuffer()
            else {
                request.finish(with: NSError(domain: "Hot Take", code: 1, userInfo: [NSLocalizedDescriptionKey: "No frame to draw on."]))
                return
            }
            // A screen recording's picture can end before its sound does. Past the last frame the picture holds
            // still instead of failing the whole render; with no frame at all it is plain black.
            var image: CIImage
            if let frame = request.sourceFrame(byTrackID: instruction.trackID) {
                self.lastFrame = frame
                image = CIImage(cvPixelBuffer: frame)
            } else if let held = self.lastFrame {
                image = CIImage(cvPixelBuffer: held)
            } else {
                image = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: request.renderContext.size))
            }
            if !instruction.transform.isIdentity {
                image = image.transformed(by: instruction.transform)
                image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            }
            let time = request.compositionTime.seconds
            if let effects = instruction.effects { image = effects.compose(image, at: time) }
            // The camera stays put when the picture zooms, and is simply absent where it has no footage.
            if let camera = instruction.camera, camera.isShowing(at: time), let pixels = request.sourceFrame(byTrackID: camera.trackID) {
                image = camera.draw(pixels, over: image)
            }
            for rendered in instruction.overlays {
                let opacity = rendered.overlay.opacity(at: time)
                guard opacity > 0.001 else { continue }
                let faded = opacity >= 0.999
                    ? rendered.image
                    : rendered.image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity))])
                image = faded.composited(over: image)
            }
            Self.context.render(image, to: output, bounds: CGRect(origin: .zero, size: request.renderContext.size), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            request.finish(withComposedVideoFrame: output)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}
}
