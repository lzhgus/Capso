// Packages/SharedKit/Sources/SharedKit/Utilities/ImageUtilities.swift
import AppKit
import CoreGraphics

public enum ImageUtilities {
    public static func nsImage(from cgImage: CGImage) -> NSImage {
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }

    public static func cgImage(from nsImage: NSImage) -> CGImage? {
        nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    public static func pngData(from cgImage: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    /// Copies an image to the pasteboard as PNG data.
    ///
    /// Writing an `NSImage` directly lets AppKit serialize it as TIFF, which
    /// makes clipboard consumers treat fresh screenshots as TIFF images even
    /// though Capso's default screenshot export format is PNG.
    @discardableResult
    public static func copyPNGToPasteboard(
        _ cgImage: CGImage,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard let data = pngData(from: cgImage) else { return false }
        let item = NSPasteboardItem()
        guard item.setData(data, forType: .png) else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    public static func jpegData(from cgImage: CGImage, quality: Double = 0.85) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    public static func dimensionString(for cgImage: CGImage) -> String {
        "\(cgImage.width) x \(cgImage.height)"
    }

    public static func scaled(_ cgImage: CGImage, maxWidth: Int, maxHeight: Int) -> CGImage? {
        let widthRatio = Double(maxWidth) / Double(cgImage.width)
        let heightRatio = Double(maxHeight) / Double(cgImage.height)
        let scale = min(widthRatio, heightRatio, 1.0)

        let newWidth = Int(Double(cgImage.width) * scale)
        let newHeight = Int(Double(cgImage.height) * scale)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    public static func resized(_ cgImage: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
