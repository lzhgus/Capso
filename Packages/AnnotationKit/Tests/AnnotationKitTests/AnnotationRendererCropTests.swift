import Testing
import CoreGraphics
@testable import AnnotationKit

@Suite("AnnotationRenderer crop")
struct AnnotationRendererCropTests {
    /// 10×10 image whose top half is red and bottom half is blue.
    private func makeSplitImage() throws -> CGImage {
        let ctx = try #require(CGContext(
            data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // CGContext origin is bottom-left: rows 0..<5 are the bottom half.
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 5))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 5, width: 10, height: 5))
        return try #require(ctx.makeImage())
    }

    private func averageColor(of image: CGImage) throws -> (r: UInt8, g: UInt8, b: UInt8) {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = try #require(CGContext(
            data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (px[0], px[1], px[2])
    }

    @Test("Crop rect in top-left coordinates keeps the top of the image")
    func cropTopStripKeepsTopPixels() throws {
        let source = try makeSplitImage()
        let output = try #require(AnnotationRenderer.render(
            sourceImage: source,
            objects: [],
            cropRect: CGRect(x: 0, y: 0, width: 10, height: 3)
        ))
        #expect(output.width == 10)
        #expect(output.height == 3)
        let color = try averageColor(of: output)
        #expect(color.r > 200, "expected red (top strip), got \(color)")
        #expect(color.b < 50)
    }

    @Test("Crop rect at the bottom keeps the bottom of the image")
    func cropBottomStripKeepsBottomPixels() throws {
        let source = try makeSplitImage()
        let output = try #require(AnnotationRenderer.render(
            sourceImage: source,
            objects: [],
            cropRect: CGRect(x: 0, y: 7, width: 10, height: 3)
        ))
        #expect(output.height == 3)
        let color = try averageColor(of: output)
        #expect(color.b > 200, "expected blue (bottom strip), got \(color)")
        #expect(color.r < 50)
    }

    @Test("Crop rect is clipped to the image bounds")
    func cropIsClippedToImage() throws {
        let source = try makeSplitImage()
        let output = try #require(AnnotationRenderer.render(
            sourceImage: source,
            objects: [],
            cropRect: CGRect(x: 6, y: -4, width: 20, height: 8)
        ))
        #expect(output.width == 4)
        #expect(output.height == 4)
    }
}
