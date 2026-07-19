import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import SharedKit

@Suite("ImageFileWriter")
struct ImageFileWriterTests {
    @Test("matches PNG format for a .png URL")
    func matchesPNGFormatForPNGURL() throws {
        let image = try makeImage(width: 4, height: 4)
        let url = URL(fileURLWithPath: "/tmp/photo.png")

        let data = try #require(ImageFileWriter.data(from: image, matchingFormatOf: url))

        #expect(writtenFormatUTI(data) == UTType.png.identifier)
    }

    @Test("matches JPEG format for a .jpg URL")
    func matchesJPEGFormatForJPEGURL() throws {
        let image = try makeImage(width: 4, height: 4)
        let url = URL(fileURLWithPath: "/tmp/photo.jpg")

        let data = try #require(ImageFileWriter.data(from: image, matchingFormatOf: url))

        #expect(writtenFormatUTI(data) == UTType.jpeg.identifier)
    }

    @Test("matches TIFF format for a .tiff URL")
    func matchesTIFFFormatForTIFFURL() throws {
        let image = try makeImage(width: 4, height: 4)
        let url = URL(fileURLWithPath: "/tmp/photo.tiff")

        let data = try #require(ImageFileWriter.data(from: image, matchingFormatOf: url))

        #expect(writtenFormatUTI(data) == UTType.tiff.identifier)
    }

    @Test("matches GIF format for a .gif URL")
    func matchesGIFFormatForGIFURL() throws {
        let image = try makeImage(width: 4, height: 4)
        let url = URL(fileURLWithPath: "/tmp/photo.gif")

        let data = try #require(ImageFileWriter.data(from: image, matchingFormatOf: url))

        #expect(writtenFormatUTI(data) == UTType.gif.identifier)
    }

    @Test("matches HEIC format for a .heic URL when an encoder is available")
    func matchesHEICFormatForHEICURLWhenEncoderAvailable() throws {
        let image = try makeImage(width: 4, height: 4)
        let url = URL(fileURLWithPath: "/tmp/photo.heic")

        guard let data = ImageFileWriter.data(from: image, matchingFormatOf: url) else {
            // Some Intel Macs lack an HEVC encoder; skip rather than fail the suite.
            return
        }

        #expect(writtenFormatUTI(data) == UTType.heic.identifier)
    }

    @Test("falls back to PNG for an unrecognized extension")
    func fallsBackToPNGForUnknownExtension() throws {
        let image = try makeImage(width: 4, height: 4)
        let url = URL(fileURLWithPath: "/tmp/photo.xyz")

        let data = try #require(ImageFileWriter.data(from: image, matchingFormatOf: url))

        #expect(writtenFormatUTI(data) == UTType.png.identifier)
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.7, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func writtenFormatUTI(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceGetType(source) as String?
    }
}
