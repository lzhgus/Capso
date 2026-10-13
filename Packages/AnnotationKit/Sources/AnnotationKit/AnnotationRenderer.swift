// Packages/AnnotationKit/Sources/AnnotationKit/AnnotationRenderer.swift
import Foundation
import CoreGraphics
import CoreImage

public enum AnnotationRenderer {
    /// Room kept around annotations that stick out of the image.
    public static let canvasMargin: CGFloat = 12

    /// The image rect grown to hold every annotation that sticks out of it, in image coordinates.
    public static func canvasRect(imageSize: CGSize, objects: [any AnnotationObject]) -> CGRect {
        let image = CGRect(origin: .zero, size: imageSize)
        // Rounding each piece (not the union) keeps the image's own edges exact.
        return objects.reduce(image) { rect, object in
            image.contains(object.bounds) ? rect : rect.union(object.bounds.insetBy(dx: -canvasMargin, dy: -canvasMargin).integral)
        }
    }

    /// Renders the source image with annotations drawn on top, optionally cropped.
    /// `cropRect` is in image coordinates with top-left origin (y grows down),
    /// matching AnnotationObject.bounds. The renderer flips to bottom-left
    /// internally before calling `CGImage.cropping(to:)`.
    /// With `expandsCanvas` (and no crop), annotations outside the image grow the
    /// output; the added area is transparent.
    public static func render(
        sourceImage: CGImage,
        objects: [any AnnotationObject],
        cropRect: CGRect? = nil,
        expandsCanvas: Bool = false
    ) -> CGImage? {
        let imageSize = CGSize(width: sourceImage.width, height: sourceImage.height)
        let canvas = expandsCanvas && cropRect == nil
            ? canvasRect(imageSize: imageSize, objects: objects)
            : CGRect(origin: .zero, size: imageSize)
        let width = Int(canvas.width)
        let height = Int(canvas.height)

        guard let ctx = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        ctx.draw(sourceImage, in: CGRect(
            x: -canvas.minX, y: canvas.maxY - imageSize.height,
            width: imageSize.width, height: imageSize.height
        ))

        ctx.saveGState()
        ctx.translateBy(x: -canvas.minX, y: canvas.maxY)
        ctx.scaleBy(x: 1, y: -1)

        SpotlightObject.renderDim(for: objects, canvas: canvas, in: ctx)
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
            let flipped = CGRect(
                x: crop.minX,
                y: CGFloat(height) - crop.maxY,
                width: crop.width,
                height: crop.height
            ).intersection(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

            if !flipped.isEmpty, let cropped = outputImage.cropping(to: flipped) {
                outputImage = cropped
            }
        }

        return outputImage
    }
}
