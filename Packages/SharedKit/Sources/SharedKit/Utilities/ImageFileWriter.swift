// Packages/SharedKit/Sources/SharedKit/Utilities/ImageFileWriter.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Encodes a rendered CGImage back into the byte format of an existing file,
/// so overwriting an opened image preserves its original format.
public enum ImageFileWriter {
    public static func data(
        from cgImage: CGImage,
        matchingFormatOf url: URL,
        quality: Double = 0.85
    ) -> Data? {
        let pathExtension = url.pathExtension.lowercased()

        if let format = FileFormat(pathExtension: pathExtension),
           let outputFormat = ScreenshotOutputFormat(format) {
            return ImageEncoders.default.encode(cgImage, format: outputFormat, quality: quality)
        }

        guard let type = UTType(filenameExtension: pathExtension) else {
            return ImageUtilities.pngData(from: cgImage)
        }
        if type.conforms(to: .tiff) {
            return NSBitmapImageRep(cgImage: cgImage).representation(using: .tiff, properties: [:])
        }
        if type.conforms(to: .gif) {
            return NSBitmapImageRep(cgImage: cgImage).representation(using: .gif, properties: [:])
        }
        return ImageUtilities.pngData(from: cgImage)
    }
}
