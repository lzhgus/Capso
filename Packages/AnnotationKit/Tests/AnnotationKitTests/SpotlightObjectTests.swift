import Testing
import CoreGraphics
@testable import AnnotationKit

@Suite("Spotlight")
struct SpotlightObjectTests {
    private let size = 200

    /// A plain white image rendered with `objects`; returns the red channel of the pixel at (x, y), top-left origin.
    private func brightness(_ objects: [any AnnotationObject]) -> (Int, Int) -> UInt8 {
        let white = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        white.setFillColor(gray: 1, alpha: 1)
        white.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let output = AnnotationRenderer.render(sourceImage: white.makeImage()!, objects: objects)!
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(output, in: CGRect(x: 0, y: 0, width: size, height: size))
        return { x, y in pixels[(y * size + x) * 4] }
    }

    @Test("Inside the spotlight stays bright, outside is dimmed")
    func dimsOutside() {
        let pixel = brightness([SpotlightObject(rect: CGRect(x: 50, y: 50, width: 60, height: 60))])
        #expect(pixel(80, 80) == 255)
        #expect(abs(Int(pixel(10, 10)) - Int(255 * (1 - SpotlightObject.dimOpacity))) <= 2)
    }

    @Test("Several spotlights share one shade, and overlaps stay bright")
    func sharedShade() {
        let pixel = brightness([
            SpotlightObject(rect: CGRect(x: 20, y: 20, width: 80, height: 80)),
            SpotlightObject(rect: CGRect(x: 60, y: 60, width: 80, height: 80)),
        ])
        #expect(pixel(40, 40) == 255)
        #expect(pixel(120, 120) == 255)
        #expect(pixel(80, 80) == 255)
        #expect(abs(Int(pixel(180, 10)) - Int(255 * (1 - SpotlightObject.dimOpacity))) <= 2)
    }

    @Test("Without spotlights nothing is dimmed")
    func noSpotlight() {
        #expect(brightness([])(10, 10) == 255)
    }

    @Test("G picks the spotlight tool")
    func shortcut() {
        #expect(AnnotationToolShortcut.tool(for: "g") == .spotlight)
    }
}
