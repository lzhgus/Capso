// Packages/SharedKit/Sources/SharedKit/Utilities/ImageFileReader.swift
import AppKit
import UniformTypeIdentifiers

public enum ImageFileReader {
    public static let supportedContentTypes: [UTType] = [.png, .jpeg, .heic, .tiff, .gif]

    public static func isSupported(_ url: URL) -> Bool {
        guard url.isFileURL,
              let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return supportedContentTypes.contains { type.conforms(to: $0) }
    }

    public static func image(at url: URL) -> CGImage? {
        guard let nsImage = NSImage(contentsOf: url) else { return nil }
        return ImageUtilities.cgImage(from: nsImage)
    }
}
