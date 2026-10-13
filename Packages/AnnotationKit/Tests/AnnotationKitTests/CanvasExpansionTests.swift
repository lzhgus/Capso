import Testing
import CoreGraphics
@testable import AnnotationKit

@Suite("Canvas expansion")
struct CanvasExpansionTests {
    private func redImage(_ size: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }

    /// RGBA of the pixel at (x, y), top-left origin.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &p, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return p
    }

    private let outside = RectangleObject(rect: CGRect(x: -40, y: 20, width: 30, height: 30))

    @Test("Annotations inside the image leave the canvas alone")
    func insideKeepsImageRect() {
        let inside = RectangleObject(rect: CGRect(x: 10, y: 10, width: 20, height: 20))
        #expect(AnnotationRenderer.canvasRect(imageSize: CGSize(width: 100, height: 100), objects: [inside])
            == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test("An annotation past the left edge grows the canvas to hold it plus a margin")
    func outsideGrowsCanvas() {
        let rect = AnnotationRenderer.canvasRect(imageSize: CGSize(width: 100, height: 100), objects: [outside])
        #expect(rect == CGRect(x: -52, y: 0, width: 152, height: 100))
    }

    @Test("Expanded output is bigger, transparent outside the image, and keeps the image in place")
    func rendersExpanded() throws {
        let output = try #require(AnnotationRenderer.render(sourceImage: redImage(100), objects: [outside], expandsCanvas: true))
        #expect(output.width == 152 && output.height == 100)
        #expect(pixel(output, 2, 2)[3] == 0)
        let first = pixel(output, 52, 80)
        #expect(first[0] > 240 && first[2] < 20 && first[3] == 255)
        #expect(pixel(output, 51, 80)[3] == 0)
        #expect(pixel(output, 52 - 40, 35)[3] == 255)
    }

    @Test("A fractional edge still puts the image on whole pixels")
    func fractionalEdge() throws {
        let object = RectangleObject(rect: CGRect(x: -40.4, y: 20, width: 30, height: 30))
        let output = try #require(AnnotationRenderer.render(sourceImage: redImage(100), objects: [object], expandsCanvas: true))
        #expect(output.width == 153)
        #expect(pixel(output, 52, 80)[3] == 0)
        #expect(pixel(output, 53, 80)[3] == 255)
        #expect(pixel(output, 152, 80)[3] == 255)
    }

    @Test("Growing to the left never adds a column on the right")
    func noRoundingSliver() {
        for x in stride(from: -400.0, to: -20.0, by: 0.1) {
            let object = RectangleObject(rect: CGRect(x: x, y: 20, width: 10, height: 10))
            let rect = AnnotationRenderer.canvasRect(imageSize: CGSize(width: 800, height: 500), objects: [object])
            #expect(rect.maxX == 800, "x = \(x)")
        }
    }

    @Test("Without expansion, or with a crop, output stays the image size")
    func noExpansionByDefault() throws {
        let plain = try #require(AnnotationRenderer.render(sourceImage: redImage(100), objects: [outside]))
        #expect(plain.width == 100)
        let cropped = try #require(AnnotationRenderer.render(
            sourceImage: redImage(100), objects: [outside],
            cropRect: CGRect(x: 10, y: 10, width: 50, height: 50), expandsCanvas: true))
        #expect(cropped.width == 50)
    }
}
