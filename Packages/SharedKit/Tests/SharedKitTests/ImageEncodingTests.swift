import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import SharedKit

@Suite("ImageEncoding")
struct ImageEncodingTests {
    private let encoder = ImageIOEncoder()

    @Test("PNG encodes to PNG bytes")
    func encodesPNG() throws {
        let data = try #require(encoder.encode(makeImage(), format: .png, quality: 1))

        #expect(encodedFormatUTI(data) == UTType.png.identifier)
    }

    @Test("JPEG encodes to JPEG bytes")
    func encodesJPEG() throws {
        let data = try #require(encoder.encode(makeImage(), format: .jpeg, quality: 0.85))

        #expect(encodedFormatUTI(data) == UTType.jpeg.identifier)
    }

    @Test("HEIC encodes to HEIC bytes when an encoder is available")
    func encodesHEIC() throws {
        // Some Intel Macs lack an HEVC encoder; skip rather than fail the suite.
        guard ScreenshotOutputFormat.heic.isAvailable else { return }

        let data = try #require(encoder.encode(makeImage(), format: .heic, quality: 0.85))

        #expect(encodedFormatUTI(data) == UTType.heic.identifier)
    }

    @Test("Lower quality produces fewer bytes for lossy formats", arguments: [ScreenshotOutputFormat.jpeg, .heic])
    func lowerQualityShrinksLossyOutput(format: ScreenshotOutputFormat) throws {
        guard format.isAvailable else { return }
        let image = makeImage()

        let low = try #require(encoder.encode(image, format: format, quality: 0.3))
        let high = try #require(encoder.encode(image, format: format, quality: 1))

        #expect(low.count < high.count)
    }

    @Test("JPEG turns transparent areas white, not black")
    func jpegFlattensOnWhite() throws {
        let clear = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let data = try #require(encoder.encode(clear, format: .jpeg, quality: 1))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixel = [UInt8](repeating: 0, count: 4)
        let ctx = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(decoded, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(pixel[0] > 245 && pixel[1] > 245 && pixel[2] > 245)
    }

    @Test("PNG ignores quality")
    func pngIgnoresQuality() throws {
        let image = makeImage()

        let low = try #require(encoder.encode(image, format: .png, quality: 0.3))
        let high = try #require(encoder.encode(image, format: .png, quality: 1))

        #expect(low == high)
    }

    @Test("An unavailable format encodes to nil rather than substituting another format")
    func unavailableFormatReturnsNil() {
        for format in ScreenshotOutputFormat.allCases where !format.isAvailable {
            #expect(encoder.encode(makeImage(), format: format, quality: 0.85) == nil)
        }
    }

    @Test("Only PNG is lossless")
    func lossyFormats() {
        #expect(ScreenshotOutputFormat.png.isLossy == false)
        #expect(ScreenshotOutputFormat.jpeg.isLossy)
        #expect(ScreenshotOutputFormat.heic.isLossy)
    }

    @Test("Output formats map to their file format and back")
    func fileFormatRoundTrip() {
        for format in ScreenshotOutputFormat.allCases {
            #expect(ScreenshotOutputFormat(format.fileFormat) == format)
        }
        #expect(ScreenshotOutputFormat(.mp4) == nil)
        #expect(ScreenshotOutputFormat(.gif) == nil)
        #expect(ScreenshotOutputFormat(.mov) == nil)
    }

    @Test("Output formats expose an image MIME type")
    func mimeTypes() {
        #expect(ScreenshotOutputFormat.png.mimeType == "image/png")
        #expect(ScreenshotOutputFormat.jpeg.mimeType == "image/jpeg")
        #expect(ScreenshotOutputFormat.heic.mimeType == "image/heic")
    }

    /// Varied content so lossy quality changes measurably alter the byte count.
    private func makeImage(width: Int = 256, height: Int = 256) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for index in 0..<400 {
            context.setFillColor(CGColor(
                red: Double(index % 97) / 97,
                green: Double(index % 53) / 53,
                blue: Double(index % 31) / 31,
                alpha: 1
            ))
            context.fill(CGRect(x: (index * 37) % width, y: (index * 61) % height, width: 19, height: 13))
        }
        return context.makeImage()!
    }

    private func encodedFormatUTI(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceGetType(source) as String?
    }
}
