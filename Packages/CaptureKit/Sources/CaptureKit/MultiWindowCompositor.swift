import AppKit
import CoreGraphics
import Foundation
import QuartzCore

/// Pure geometry helpers for compositing multiple window screenshots onto one
/// transparent canvas. Frames use ScreenCaptureKit global coordinates (origin
/// at the top-left of the primary display, Y increasing downward).
enum MultiWindowCompositor {

    /// Continuous corner radius (points) matching recent macOS window chrome.
    static let fallbackCornerRadiusPoints: CGFloat = 16

    /// Inset applied to the corner mask so soft anti-aliased fringe pixels
    /// (often light/white against a dark backdrop) are clipped away.
    static let cornerMaskInsetPoints: CGFloat = 0.75

    /// Alpha below this is forced to 0 after masking — kills residual soft
    /// white halos without touching fully opaque window chrome.
    static let softAlphaThreshold: UInt8 = 24

    struct Layer: Sendable {
        let image: CGImage
        /// Window frame in ScreenCaptureKit global point coordinates.
        let frame: CGRect

        init(image: CGImage, frame: CGRect) {
            self.image = image
            self.frame = frame
        }
    }

    /// Axis-aligned union of the given frames. Returns `nil` when `frames` is empty.
    static func unionBounds(of frames: [CGRect]) -> CGRect? {
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    /// Composite layers onto a transparent canvas sized to the union of their
    /// frames. `layers` is front-to-back (index 0 = frontmost); drawing walks
    /// the array in reverse so earlier entries end on top.
    ///
    /// Gaps between windows stay fully transparent (alpha 0). Each layer is
    /// pre-masked with a continuous corner silhouette (slightly inset) so
    /// square/white corner fringes do not survive into the composite.
    static func composite(
        layers: [Layer],
        cornerRadiusPoints: CGFloat = fallbackCornerRadiusPoints
    ) -> CGImage? {
        guard !layers.isEmpty else { return nil }
        guard let union = unionBounds(of: layers.map(\.frame)),
              union.width > 0, union.height > 0 else {
            return nil
        }

        let scale = layers.map { layer -> CGFloat in
            guard layer.frame.width > 0 else { return 2 }
            return CGFloat(layer.image.width) / layer.frame.width
        }.max() ?? 2

        let pixelWidth = max(1, Int((union.width * scale).rounded()))
        let pixelHeight = max(1, Int((union.height * scale).rounded()))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        // Prefer crisp edges over soft resampling fringe when sizes differ by a px.
        context.interpolationQuality = .medium

        for layer in layers.reversed() {
            let prepared = prepareLayerImage(
                layer.image,
                pointSize: layer.frame.size,
                cornerRadiusPoints: cornerRadiusPoints
            ) ?? layer.image

            let localX = layer.frame.minX - union.minX
            let localTopY = layer.frame.minY - union.minY
            let localBottomY = union.height - localTopY - layer.frame.height
            let dest = CGRect(
                x: localX * scale,
                y: localBottomY * scale,
                width: layer.frame.width * scale,
                height: layer.frame.height * scale
            )
            context.draw(prepared, in: dest)
        }

        return context.makeImage()
    }

    /// Mask a captured window bitmap to a continuous rounded rect and harden
    /// soft alpha. Exposed for unit tests.
    static func prepareLayerImage(
        _ image: CGImage,
        pointSize: CGSize,
        cornerRadiusPoints: CGFloat,
        insetPoints: CGFloat = cornerMaskInsetPoints,
        softAlphaThreshold: UInt8 = softAlphaThreshold
    ) -> CGImage? {
        let masked: CGImage
        if cornerRadiusPoints > 0,
           let continuous = applyContinuousCornerMask(
               to: image,
               pointSize: pointSize,
               cornerRadiusPoints: cornerRadiusPoints,
               insetPoints: insetPoints
           ) {
            masked = continuous
        } else {
            masked = image
        }
        return hardenSoftAlpha(masked, threshold: softAlphaThreshold) ?? masked
    }

    // MARK: - Corner mask

    private static func applyContinuousCornerMask(
        to image: CGImage,
        pointSize: CGSize,
        cornerRadiusPoints: CGFloat,
        insetPoints: CGFloat
    ) -> CGImage? {
        let pw = image.width
        let ph = image.height
        guard pw > 0, ph > 0, pointSize.width > 0, pointSize.height > 0 else { return nil }

        guard let mask = continuousCornerMask(
            pixelWidth: pw,
            pixelHeight: ph,
            pointSize: pointSize,
            cornerRadiusPoints: cornerRadiusPoints,
            insetPoints: insetPoints
        ) else {
            return nil
        }

        let colorSpace: CGColorSpace = {
            if let cs = image.colorSpace, cs.model == .rgb { return cs }
            return CGColorSpaceCreateDeviceRGB()
        }()

        guard let context = CGContext(
            data: nil,
            width: pw,
            height: ph,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: pw, height: ph)
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        // Multiply destination alpha by the continuous mask silhouette.
        context.setBlendMode(.destinationIn)
        context.draw(mask, in: rect)
        return context.makeImage()
    }

    private static func continuousCornerMask(
        pixelWidth: Int,
        pixelHeight: Int,
        pointSize: CGSize,
        cornerRadiusPoints: CGFloat,
        insetPoints: CGFloat
    ) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let scaleX = CGFloat(pixelWidth) / pointSize.width
        let scaleY = CGFloat(pixelHeight) / pointSize.height
        let scale = max(scaleX, scaleY)
        let inset = max(0, insetPoints)
        let drawableSize = CGSize(
            width: max(1, pointSize.width - inset * 2),
            height: max(1, pointSize.height - inset * 2)
        )
        let radius = min(
            cornerRadiusPoints,
            min(drawableSize.width, drawableSize.height) / 2
        )

        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.translateBy(x: inset * scaleX, y: inset * scaleY)
        context.scaleBy(x: scaleX, y: scaleY)

        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: drawableSize)
        layer.backgroundColor = NSColor.white.cgColor
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.contentsScale = scale
        layer.rasterizationScale = scale
        layer.masksToBounds = true
        layer.render(in: context)

        return context.makeImage()
    }

    // MARK: - Soft alpha cleanup

    /// Force nearly-transparent fringe pixels to fully transparent so light
    /// premultiplied RGB cannot read as a white halo on dark backgrounds.
    private static func hardenSoftAlpha(_ image: CGImage, threshold: UInt8) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let drew = pixels.withUnsafeMutableBytes { ptr -> Bool in
            guard let context = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        for i in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let alpha = pixels[i + 3]
            if alpha < threshold {
                pixels[i] = 0
                pixels[i + 1] = 0
                pixels[i + 2] = 0
                pixels[i + 3] = 0
            }
        }

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let out = context.makeImage() else {
            return nil
        }
        return out
    }
}
