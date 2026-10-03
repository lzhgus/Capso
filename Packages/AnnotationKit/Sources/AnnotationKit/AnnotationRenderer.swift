// Packages/AnnotationKit/Sources/AnnotationKit/AnnotationRenderer.swift
import Foundation
import CoreGraphics
import CoreImage

public enum AnnotationRenderer {
    /// Renders the source image with annotations drawn on top, optionally cropped.
    /// `cropRect` is in image coordinates with top-left origin (y grows down),
    /// matching AnnotationObject.bounds. `CGImage.cropping(to:)` uses the same
    /// top-left pixel space, so the rect is passed through unchanged.
    public static func render(
        sourceImage: CGImage,
        objects: [any AnnotationObject],
        cropRect: CGRect? = nil
    ) -> CGImage? {
        let width = sourceImage.width
        let height = sourceImage.height

        guard let ctx = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        ctx.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        for object in objects {
            if let pixelate = object as? PixelateObject {
                pixelate.renderWithSource(in: ctx, sourceImage: sourceImage)
            } else {
                object.render(in: ctx)
            }
        }
        ctx.restoreGState()

        guard var outputImage = ctx.makeImage() else { return nil }

        if let crop = cropRect {
            let clipped = crop.intersection(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            if !clipped.isEmpty, let cropped = outputImage.cropping(to: clipped) {
                outputImage = cropped
            }
        }

        return outputImage
    }
}
