import CoreGraphics

public enum CaptureGeometry {
    /// AppKit rects have a bottom-left origin; ScreenCaptureKit's `sourceRect` is top-left.
    /// `rect` is relative to the display; the result is rounded to whole points.
    public static func topLeftRect(fromBottomLeft rect: CGRect, displayHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: displayHeight - rect.maxY, width: rect.width, height: rect.height).integral
    }

    /// Output pixel size for a region of `points` at `scale`, rounded down to even numbers
    /// because H.264 needs even dimensions. Never smaller than 2×2.
    public static func evenPixelSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        func even(_ value: CGFloat) -> Int { max(2, Int(value * scale) / 2 * 2) }
        return (even(points.width), even(points.height))
    }
}
