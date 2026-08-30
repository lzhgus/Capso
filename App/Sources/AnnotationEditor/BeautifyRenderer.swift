import AppKit
import CoreGraphics
import CoreImage
import SwiftUI

enum BeautifyRenderer {
    static func render(image: CGImage, settings: BeautifySettings) -> CGImage? {
        guard settings.isEnabled else { return image }

        let padding = max(0, settings.padding)
        let cornerRadius = max(0, settings.cornerRadius)
        let shadowRadius = settings.shadowEnabled ? max(0, settings.shadowRadius) : 0
        let shadowInset = settings.shadowEnabled ? shadowRadius + 6 : 0
        let outputWidth = Int(CGFloat(image.width) + (padding + shadowInset) * 2)
        let outputHeight = Int(CGFloat(image.height) + (padding + shadowInset) * 2)

        guard let ctx = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: outputWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let canvasRect = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)

        switch settings.backgroundStyle {
        case .solid:
            let bgColor = NSColor(settings.backgroundColor).cgColor
            ctx.setFillColor(bgColor)
            ctx.fill(canvasRect)

        case .liquidGlass:
            // Fall back to a dark fill if CI fails for any reason.
            ctx.setFillColor(NSColor(calibratedWhite: 0.1, alpha: 1).cgColor)
            ctx.fill(canvasRect)

            if let backdrop = liquidGlassBackdrop(from: image, targetSize: canvasRect.size) {
                // CGContext.draw(_:in:) renders CGImages right-side-up in a
                // bottom-left CGBitmapContext — no y-flip required. Same as
                // AnnotationRenderer does with the source image.
                ctx.draw(backdrop, in: canvasRect)
            }

            // Subtle white sheen so the glass feels slightly brightened.
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.03).cgColor)
            ctx.fill(canvasRect)
        }

        let imageRect = CGRect(
            x: padding + shadowInset,
            y: padding + shadowInset,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )

        if settings.shadowEnabled {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: shadowRadius, color: NSColor.black.withAlphaComponent(0.25).cgColor)
            let shadowPath = CGPath(roundedRect: imageRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            ctx.addPath(shadowPath)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.saveGState()
        let clipPath = CGPath(roundedRect: imageRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(clipPath)
        ctx.clip()
        // No y-flip: CGContext.draw(_:in:) already renders CGImages right-side-up
        // in a bottom-left CGBitmapContext. (AnnotationRenderer does the same.)
        // The previous flip was a long-standing bug that went unnoticed with
        // solid backgrounds because users mostly inspected the editor preview.
        ctx.draw(image, in: imageRect)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    /// Build a "liquid glass" backdrop: an aspect-fill copy of the source
    /// image, saturation-boosted and heavily Gaussian-blurred, rendered to
    /// exactly `targetSize`. The resulting image extends the screenshot's own
    /// colours into the padding area around the final output.
    private static func liquidGlassBackdrop(from image: CGImage, targetSize: CGSize) -> CGImage? {
        let srcW = CGFloat(image.width)
        let srcH = CGFloat(image.height)
        guard srcW > 0, srcH > 0, targetSize.width > 0, targetSize.height > 0 else { return nil }

        // Aspect-fill scale, with a slight overshoot so the blur never reveals
        // hard edges inside the canvas.
        let coverScale = max(targetSize.width / srcW, targetSize.height / srcH)
        let scale = coverScale * 1.15

        var ci = CIImage(cgImage: image)
        ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Centre the scaled image on the target canvas.
        let tx = (targetSize.width - ci.extent.width) / 2 - ci.extent.minX
        let ty = (targetSize.height - ci.extent.height) / 2 - ci.extent.minY
        ci = ci.transformed(by: CGAffineTransform(translationX: tx, y: ty))

        // Boost saturation for a richer, glass-like colour bloom.
        if let f = CIFilter(name: "CIColorControls", parameters: [
            kCIInputImageKey: ci,
            kCIInputSaturationKey: 1.9,
            kCIInputBrightnessKey: 0.0,
            kCIInputContrastKey: 0.95,
        ]), let out = f.outputImage {
            ci = out
        }

        // Clamp before blurring so edges don't fade to transparent/black.
        let clamped = ci.clampedToExtent()
        if let f = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: clamped,
            kCIInputRadiusKey: 120.0,
        ]), let out = f.outputImage {
            ci = out
        }

        let context = CIContext(options: [.cacheIntermediates: false])
        let target = CGRect(origin: .zero, size: targetSize)
        return context.createCGImage(ci, from: target)
    }
}
