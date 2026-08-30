// Packages/HistoryKit/Sources/HistoryKit/ThumbnailGenerator.swift
import AppKit
import CoreGraphics

/// Generates JPEG thumbnails from full-resolution CGImages.
public enum ThumbnailGenerator {
    /// Target thumbnail width in pixels (2× for Retina).
    private static let thumbnailWidth = 640

    /// Generate a JPEG thumbnail from a full-resolution image.
    /// Returns nil if the image cannot be resized or encoded.
    public static func generateThumbnail(from image: CGImage, quality: Double = 0.7) -> Data? {
        autoreleasepool {
            let scale = Double(thumbnailWidth) / Double(image.width)
            let thumbWidth = thumbnailWidth
            let thumbHeight = Int(Double(image.height) * scale)

            guard thumbWidth > 0, thumbHeight > 0 else { return nil }

            guard let context = CGContext(
                data: nil,
                width: thumbWidth,
                height: thumbHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return nil }

            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight))

            guard let thumbImage = context.makeImage() else { return nil }

            let rep = NSBitmapImageRep(cgImage: thumbImage)
            return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }
    }
}
