import AppKit
import CoreGraphics
import Testing
@testable import SharedKit

@Suite("ImageUtilities")
struct ImageUtilitiesTests {
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
