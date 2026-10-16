import AppKit
import CoreGraphics
import Testing
@testable import SharedKit

@Suite("ImageUtilities")
struct ImageUtilitiesTests {
    @Test("Thin screenshots retain a pixel on their shortest edge")
    func thinScreenshotScaling() throws {
        for (width, height) in [(1, 4096), (4096, 1)] {
            let image = try makeSolidImage(width: width, height: height, color: CGColor(gray: 0.5, alpha: 1))
            let scaled = try #require(ImageUtilities.scaled(image, maxWidth: 536, maxHeight: 284))
            #expect(scaled.width >= 1 && scaled.width <= 536)
            #expect(scaled.height >= 1 && scaled.height <= 284)
        }
    }

    @Test("Small images are reused and invalid thumbnail bounds are rejected")
    func scalingBoundsAndReuse() throws {
        let image = try makeSolidImage(width: 8, height: 6, color: CGColor(gray: 0.5, alpha: 1))
        #expect(ImageUtilities.scaled(image, maxWidth: 536, maxHeight: 284) === image)
        #expect(ImageUtilities.scaled(image, maxWidth: 0, maxHeight: 284) == nil)
        #expect(ImageUtilities.scaled(image, maxWidth: 536, maxHeight: -1) == nil)
    }

    @Test("Exact resize creates requested pixel dimensions")
    func exactResizeCreatesRequestedPixelDimensions() throws {
        let image = try makeSolidImage(width: 12, height: 8, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))

        let resized = try #require(ImageUtilities.resized(image, width: 5, height: 7))

        #expect(resized.width == 5)
        #expect(resized.height == 7)
    }

    @Test("Exact resize can upscale")
    func exactResizeCanUpscale() throws {
        let image = try makeSolidImage(width: 4, height: 4, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))

        let resized = try #require(ImageUtilities.resized(image, width: 9, height: 6))

        #expect(resized.width == 9)
        #expect(resized.height == 6)
    }

    @Test("Screenshot clipboard writes the selected image format")
    func screenshotClipboardWritesSelectedFormat() throws {
        let image = try makeSolidImage(
            width: 8,
            height: 6,
            color: CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        )
        let cases: [(ScreenshotClipboardFormat, NSPasteboard.PasteboardType)] = [
            (.png, .png),
            (.jpeg, ImageUtilities.jpegPasteboardType),
            (.tiff, .tiff),
        ]

        for (format, expectedType) in cases {
            let pasteboard = NSPasteboard(
                name: NSPasteboard.Name("CapsoImageUtilitiesTests.\(UUID().uuidString)")
            )

            #expect(ImageUtilities.copyToPasteboard(image, format: format, pasteboard: pasteboard))
            #expect(pasteboard.types?.first == expectedType)
            #expect(pasteboard.data(forType: expectedType) != nil)
        }
    }
}

private func makeSolidImage(width: Int, height: Int, color: CGColor) throws -> CGImage {
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(color)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}
