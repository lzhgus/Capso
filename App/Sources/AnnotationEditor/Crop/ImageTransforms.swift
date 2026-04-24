// App/Sources/AnnotationEditor/Crop/ImageTransforms.swift
import CoreGraphics

/// Core Graphics helpers for the one-click rotate / flip operations in the
/// crop editor. Each returns a newly-allocated CGImage; the input is not
/// modified. Returns nil on allocation failure (extremely rare).
enum ImageTransforms {
    /// Rotate the image 90° counter-clockwise. Output dimensions are swapped.
    static func rotate90CCW(_ image: CGImage) -> CGImage? {
        let w = image.width
        let h = image.height
        guard let ctx = CGContext(
            data: nil,
            width: h, height: w,  // dimensions swap
            bitsPerComponent: 8,
            bytesPerRow: h * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // CCW rotation: translate to new-origin, rotate +90° (CGContext is
        // counter-clockwise positive), draw at original size.
        ctx.translateBy(x: 0, y: CGFloat(w))
        ctx.rotate(by: -.pi / 2)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Mirror the image horizontally. Output dimensions are unchanged.
    static func flipHorizontal(_ image: CGImage) -> CGImage? {
        let w = image.width
        let h = image.height
        guard let ctx = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        ctx.translateBy(x: CGFloat(w), y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}

/// Rect-math helpers for remapping the in-editor crop rect whenever the
/// backing image is rotated or flipped. Coordinate conventions match
/// AnnotationCanvasNSView: top-left origin, y grows down.
enum RectTransforms {
    /// Remap a rect living in `oldSize` through a 90° CCW image rotation.
    /// The output's coordinate space is the rotated image's (swapped dims).
    static func rotate90CCW(_ rect: CGRect, in oldSize: CGSize) -> CGRect {
        return CGRect(
            x: rect.minY,
            y: oldSize.width - rect.maxX,
            width: rect.height,
            height: rect.width
        )
    }

    /// Mirror a rect horizontally within an image of the given size.
    static func flipHorizontal(_ rect: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: size.width - rect.maxX,
            y: rect.minY,
            width: rect.width,
            height: rect.height
        )
    }
}
