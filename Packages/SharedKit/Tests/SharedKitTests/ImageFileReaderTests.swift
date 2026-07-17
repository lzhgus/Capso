import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import SharedKit

@Suite("ImageFileReader")
struct ImageFileReaderTests {
    @Test("supported content types cover issue formats")
    func supportedContentTypesCoverIssueFormats() {
        let types = ImageFileReader.supportedContentTypes
        #expect(types.contains(.png))
        #expect(types.contains(.jpeg))
        #expect(types.contains(.heic))
        #expect(types.contains(.tiff))
        #expect(types.contains(.gif))
    }

    @Test("accepts image extensions case-insensitively")
    func isSupportedAcceptsImageExtensionsCaseInsensitively() {
        for name in ["b.PNG", "b.jpg", "b.jpeg", "b.heic", "b.tif", "b.tiff", "b.gif"] {
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            #expect(ImageFileReader.isSupported(url), "expected \(name) to be supported")
        }
    }

    @Test("rejects non-image and non-file URLs")
    func isSupportedRejectsNonImageAndNonFileURLs() throws {
        #expect(!ImageFileReader.isSupported(URL(fileURLWithPath: "/tmp/x.pdf")))
        #expect(!ImageFileReader.isSupported(URL(fileURLWithPath: "/tmp/x.txt")))
        #expect(!ImageFileReader.isSupported(URL(fileURLWithPath: "/tmp/x")))
        let remoteURL = try #require(URL(string: "capso://grab/area"))
        #expect(!ImageFileReader.isSupported(remoteURL))
    }

    @Test("loads PNG at original pixel size")
    func loadsPNGAtOriginalPixelSize() throws {
        let image = try makeImage(width: 9, height: 4)
        let url = try writeImage(image, extension: "png", using: .png)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try #require(ImageFileReader.image(at: url))

        #expect(loaded.width == 9)
        #expect(loaded.height == 4)
    }

    @Test("loads JPEG, TIFF, and GIF")
    func loadsJPEGTIFFAndGIF() throws {
        let image = try makeImage(width: 6, height: 3)

        for (ext, type) in [("jpg", NSBitmapImageRep.FileType.jpeg), ("tiff", .tiff), ("gif", .gif)] {
            let url = try writeImage(image, extension: ext, using: type)
            defer { try? FileManager.default.removeItem(at: url) }

            let loaded = try #require(ImageFileReader.image(at: url), "failed to load .\(ext)")

            #expect(loaded.width == 6, "unexpected width for .\(ext)")
            #expect(loaded.height == 3, "unexpected height for .\(ext)")
        }
    }

    @Test("loads HEIC when an encoder is available")
    func loadsHEICWhenEncoderAvailable() throws {
        let image = try makeImage(width: 5, height: 5)
        guard let url = writeHEIC(image) else {
            // Some Intel Macs lack an HEVC encoder; skip rather than fail the suite.
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try #require(ImageFileReader.image(at: url))

        #expect(loaded.width == 5)
        #expect(loaded.height == 5)
    }

    @Test("returns nil for corrupt data")
    func returnsNilForCorruptData() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-imagefile-\(UUID().uuidString)")
            .appendingPathExtension("png")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(ImageFileReader.image(at: url) == nil)
    }

    @Test("returns nil for a missing file")
    func returnsNilForMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-imagefile-missing-\(UUID().uuidString)")
            .appendingPathExtension("png")

        #expect(ImageFileReader.image(at: url) == nil)
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
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func writeImage(_ cgImage: CGImage, extension ext: String, using type: NSBitmapImageRep.FileType) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-imagefile-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let data = try #require(rep.representation(using: type, properties: [:]))
        try data.write(to: url)
        return url
    }

    private func writeHEIC(_ cgImage: CGImage) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-imagefile-\(UUID().uuidString)")
            .appendingPathExtension("heic")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.heic.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }
}
