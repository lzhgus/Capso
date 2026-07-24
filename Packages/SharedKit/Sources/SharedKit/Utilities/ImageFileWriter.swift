// Packages/SharedKit/Sources/SharedKit/Utilities/ImageFileWriter.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Encodes a rendered CGImage back into the byte format of an existing file,
/// so overwriting an opened image preserves its original format.
public enum ImageFileWriter {
    public static func data(from cgImage: CGImage, matchingFormatOf url: URL) -> Data? {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return ImageUtilities.pngData(from: cgImage)
        }

        if type.conforms(to: .jpeg) {
            return ImageUtilities.jpegData(from: cgImage)
        }
        if type.conforms(to: .heic) {
            return heicData(from: cgImage)
        }
        if type.conforms(to: .tiff) {
            return NSBitmapImageRep(cgImage: cgImage).representation(using: .tiff, properties: [:])
        }
        if type.conforms(to: .gif) {
            return NSBitmapImageRep(cgImage: cgImage).representation(using: .gif, properties: [:])
        }
        return ImageUtilities.pngData(from: cgImage)
    }

    private static func heicData(from cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData, UTType.heic.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
