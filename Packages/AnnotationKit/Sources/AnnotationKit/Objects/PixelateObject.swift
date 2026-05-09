import Foundation
import CoreGraphics
import CoreImage

public final class PixelateObject: AnnotationObject, @unchecked Sendable {
    public let id = ObjectID()
    public var style: StrokeStyle
    public var rect: CGRect
    public var blockSize: CGFloat = 12
    public var mode: RedactionMode

    public init(rect: CGRect, blockSize: CGFloat = 12, mode: RedactionMode = .pixelate) {
        self.rect = rect
        self.style = StrokeStyle()
        self.blockSize = blockSize
        self.mode = mode
    }

    public var bounds: CGRect { rect }

    public func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        rect.insetBy(dx: -threshold, dy: -threshold).contains(point)
    }

    public func render(in ctx: CGContext) {
        ctx.saveGState()
        switch mode {
        case .solid:
            ctx.setAlpha(style.opacity)
            ctx.setFillColor(style.color.cgColor)
            ctx.fill(rect)
        case .pixelate, .blur:
            ctx.setFillColor(CGColor(gray: 0.5, alpha: 0.3))
            ctx.fill(rect)
            ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.2))
            ctx.setLineWidth(0.5)
            var x = rect.minX
            while x <= rect.maxX {
                ctx.move(to: CGPoint(x: x, y: rect.minY))
                ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += blockSize
            }
            var y = rect.minY
            while y <= rect.maxY {
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += blockSize
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Apply the selected redaction filter on the source image region.
    /// `rect` is in image coordinates (top-left origin, matching source image pixel dimensions).
    /// The CGContext is assumed to be in a flipped coordinate system (isFlipped NSView).
    public func renderWithSource(in ctx: CGContext, sourceImage: CGImage) {
        guard rect.width > 0, rect.height > 0 else { return }

        if mode == .solid {
            render(in: ctx)
            return
        }

        let imgH = CGFloat(sourceImage.height)

        // CGImage.cropping uses bottom-left origin — flip Y
        let cropRect = CGRect(
            x: rect.origin.x,
            y: imgH - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        ).intersection(CGRect(x: 0, y: 0, width: CGFloat(sourceImage.width), height: imgH))

        guard !cropRect.isEmpty, let cropped = sourceImage.cropping(to: cropRect) else { return }

        let redacted: CGImage?

        switch mode {
        case .pixelate:
            redacted = Self.makePixelatedImage(from: cropped, blockSize: blockSize)
        case .blur:
            let ciImage = CIImage(cgImage: cropped)
            let filter = CIFilter(name: "CIGaussianBlur")
            filter?.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
            filter?.setValue(max(4, blockSize * 0.9), forKey: kCIInputRadiusKey)
            if let outputImage = filter?.outputImage?.cropped(to: ciImage.extent) {
                redacted = CIContext().createCGImage(outputImage, from: ciImage.extent)
            } else {
                redacted = nil
            }
        case .solid:
            redacted = nil
        }

        guard let redacted else { return }

        // Draw pixelated result — flip for CGContext.draw in flipped coordinate system
        ctx.saveGState()
        if mode == .pixelate {
            ctx.interpolationQuality = .none
        }
        ctx.translateBy(x: rect.origin.x, y: rect.origin.y + rect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(redacted, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    private static func makePixelatedImage(from image: CGImage, blockSize: CGFloat) -> CGImage? {
        let block = max(4, Int(blockSize.rounded()))
        let tinyWidth = max(1, image.width / block)
        let tinyHeight = max(1, image.height / block)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let downsampledContext = CGContext(
            data: nil,
            width: tinyWidth,
            height: tinyHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        downsampledContext.interpolationQuality = .low
        downsampledContext.draw(image, in: CGRect(x: 0, y: 0, width: tinyWidth, height: tinyHeight))
        guard let downsampled = downsampledContext.makeImage() else { return nil }

        let chunkyWidth = max(1, tinyWidth / 2)
        let chunkyHeight = max(1, tinyHeight / 2)
        guard let chunkyContext = CGContext(
            data: nil,
            width: chunkyWidth,
            height: chunkyHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        chunkyContext.interpolationQuality = .low
        chunkyContext.draw(downsampled, in: CGRect(x: 0, y: 0, width: chunkyWidth, height: chunkyHeight))
        guard let chunky = chunkyContext.makeImage() else { return nil }

        guard let outputContext = CGContext(
            data: nil,
            width: max(1, image.width),
            height: max(1, image.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        outputContext.interpolationQuality = .none
        outputContext.draw(chunky, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return outputContext.makeImage()
    }

    public func move(by delta: CGSize) {
        rect.origin.x += delta.width
        rect.origin.y += delta.height
    }

    public func copy() -> any AnnotationObject {
        let copy = PixelateObject(rect: rect, blockSize: blockSize, mode: mode)
        copy.style = style
        return copy
    }
}
