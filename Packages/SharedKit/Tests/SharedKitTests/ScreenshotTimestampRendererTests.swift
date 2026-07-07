import AppKit
import CoreGraphics
import Testing
@testable import SharedKit

@Suite("ScreenshotTimestampRenderer")
struct ScreenshotTimestampRendererTests {
    @Test("Renderer keeps image size and changes pixels when enabled")
    func rendererKeepsImageSizeAndChangesPixelsWhenEnabled() throws {
        let image = try makeSolidImage(width: 320, height: 180, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        let date = Date(timeIntervalSince1970: 1_705_348_800)
        let options = ScreenshotTimestampOptions(
            isEnabled: true,
            position: .bottomRight,
            format: .dateTime,
            colorHex: "#000000",
            fontSize: 20
        )

        let rendered = try #require(ScreenshotTimestampRenderer.render(image: image, date: date, options: options))

        #expect(rendered.width == image.width)
        #expect(rendered.height == image.height)
        #expect(try pixelData(rendered) != pixelData(image))
    }

    @Test("Renderer returns original image when disabled")
    func rendererReturnsOriginalWhenDisabled() throws {
        let image = try makeSolidImage(width: 64, height: 64, color: CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        let options = ScreenshotTimestampOptions(isEnabled: false)

        let rendered = ScreenshotTimestampRenderer.render(image: image, date: Date(), options: options)

        #expect(rendered === image)
    }
}

private func pixelData(_ image: CGImage) throws -> [UInt8] {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try pixels.withUnsafeMutableBytes { buffer in
        try #require(CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixels
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
