import AppKit
import Testing
@testable import SharedKit

@Suite("ClipboardImageReader")
struct ClipboardImageReaderTests {
    @Test("reads image objects from the pasteboard")
    func readsImageObjects() throws {
        let pasteboard = makePasteboard()
        let image = try makeImage(width: 7, height: 5)
        pasteboard.writeObjects([ImageUtilities.nsImage(from: image)])

        let result = try #require(ClipboardImageReader.image(from: pasteboard))

        #expect(result.width == 7)
        #expect(result.height == 5)
    }

    @Test("reads image file URLs from the pasteboard")
    func readsImageFileURLs() throws {
        let pasteboard = makePasteboard()
        let image = try makeImage(width: 9, height: 4)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-clipboard-\(UUID().uuidString)")
            .appendingPathExtension("png")
        try #require(ImageUtilities.pngData(from: image)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        pasteboard.writeObjects([url as NSURL])

        let result = try #require(ClipboardImageReader.image(from: pasteboard))

        #expect(result.width == 9)
        #expect(result.height == 4)
    }

    @Test("returns nil when the pasteboard has no image")
    func returnsNilWithoutImage() throws {
        let pasteboard = makePasteboard()
        pasteboard.setString("not an image", forType: .string)

        #expect(ClipboardImageReader.image(from: pasteboard) == nil)
    }

    private func makePasteboard() -> NSPasteboard {
        let name = NSPasteboard.Name("CapsoClipboardImageReaderTests.\(UUID().uuidString)")
        let pasteboard = NSPasteboard(name: name)
        pasteboard.clearContents()
        return pasteboard
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
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }
}
