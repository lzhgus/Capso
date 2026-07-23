// Packages/SharedKit/Sources/SharedKit/Utilities/ImageUtilities.swift
import AppKit
import CoreGraphics

public enum ImageUtilities {
    static let jpegPasteboardType = NSPasteboard.PasteboardType("public.jpeg")

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

    public static func tiffData(from cgImage: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .tiff, properties: [:])
    }

    /// Copies an explicitly encoded image to the pasteboard.
    ///
    /// Writing an `NSImage` directly lets AppKit choose TIFF. Encoding first
    /// keeps the pasteboard type aligned with the user's clipboard preference.
    @discardableResult
    public static func copyToPasteboard(
        _ cgImage: CGImage,
        format: ScreenshotClipboardFormat,
        jpegQuality: Double = 0.85,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        let data: Data?
        let pasteboardType: NSPasteboard.PasteboardType

        switch format {
        case .png:
            data = pngData(from: cgImage)
            pasteboardType = .png
        case .jpeg:
            data = jpegData(from: cgImage, quality: jpegQuality)
            pasteboardType = jpegPasteboardType
        case .tiff:
            data = tiffData(from: cgImage)
            pasteboardType = .tiff
        }

        guard let data else { return false }
        let item = NSPasteboardItem()
        guard item.setData(data, forType: pasteboardType) else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    @discardableResult
    public static func copyPNGToPasteboard(
        _ cgImage: CGImage,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        copyToPasteboard(cgImage, format: .png, pasteboard: pasteboard)
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
