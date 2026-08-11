// Packages/SharedKit/Sources/SharedKit/Utilities/ImageEncoding.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes a rendered image into the bytes of a chosen output format.
public protocol ImageEncoding: Sendable {
    /// Returns nil when the format cannot be encoded, so callers can surface a failure
    /// rather than write bytes that disagree with the file's extension.
    func encode(_ image: CGImage, format: ScreenshotOutputFormat, quality: Double) -> Data?
}

/// Encodes through ImageIO, covering every format macOS can write natively.
public struct ImageIOEncoder: ImageEncoding {
    public init() {}

    static let writableTypeIdentifiers: Set<String> = {
        guard let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] else { return [] }
        return Set(identifiers)
    }()

    public func encode(_ image: CGImage, format: ScreenshotOutputFormat, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, format.fileFormat.contentType.identifier as CFString, 1, nil
        ) else {
            return nil
        }

        let properties = format.isLossy
            ? [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
            : nil
        CGImageDestinationAddImage(destination, image, properties)

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

public enum ImageEncoders {
    /// The encoder used app-wide. WebP support arrives by pointing this at an encoder
    /// that handles WebP itself and delegates the rest to `ImageIOEncoder`.
    public static let `default`: any ImageEncoding = ImageIOEncoder()
}
