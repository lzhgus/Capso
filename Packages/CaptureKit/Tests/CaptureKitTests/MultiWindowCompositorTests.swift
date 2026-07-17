import Testing
import CoreGraphics
@testable import CaptureKit

@Suite("MultiWindowCompositor")
struct MultiWindowCompositorTests {

    @Test("unionBounds returns nil for empty input")
    func unionEmpty() {
        #expect(MultiWindowCompositor.unionBounds(of: []) == nil)
    }

    @Test("unionBounds unions overlapping and disjoint frames")
    func unionFrames() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 80)
        let b = CGRect(x: 50, y: 40, width: 100, height: 80)
        let union = MultiWindowCompositor.unionBounds(of: [a, b])
        #expect(union == CGRect(x: 0, y: 0, width: 150, height: 120))

        let c = CGRect(x: 200, y: 200, width: 50, height: 50)
        let disjoint = MultiWindowCompositor.unionBounds(of: [a, c])
        #expect(disjoint == CGRect(x: 0, y: 0, width: 250, height: 250))
    }

    @Test("composite draws frontmost layer on top")
    func compositeZOrder() {
        // Back layer: opaque red 40x40 at (0,0)
        let back = makeSolidImage(width: 40, height: 40, rgba: (1, 0, 0, 1))
        // Front layer: opaque blue 40x40 overlapping at (20,20)
        let front = makeSolidImage(width: 40, height: 40, rgba: (0, 0, 1, 1))

        let layers = [
            MultiWindowCompositor.Layer(
                image: front,
                frame: CGRect(x: 20, y: 20, width: 40, height: 40)
            ),
            MultiWindowCompositor.Layer(
                image: back,
                frame: CGRect(x: 0, y: 0, width: 40, height: 40)
            ),
        ]

        // Disable corner masking so solid test rects stay fully opaque.
        let image = MultiWindowCompositor.composite(layers: layers, cornerRadiusPoints: 0)
        #expect(image != nil)
        guard let image else { return }

        // Canvas is 60x60 points at 1x (images are 40px for 40pt frames).
        #expect(image.width == 60)
        #expect(image.height == 60)

        // Overlap center ≈ (30, 30) in top-left SC space → bitmap (30, 29)
        // because Y flips (bottom-left). Sample a pixel firmly inside the
        // overlap in bitmap coords.
        let overlapPixel = samplePixel(image, x: 30, y: 29)
        #expect(overlapPixel.b > overlapPixel.r)
        #expect(overlapPixel.b > 0.5)

        // Non-overlapping corner of the back layer (top-left SC → top of bitmap
        // after flip is high Y). Point (5,5) SC → bitmap y = 60 - 5 - 1 = 54.
        let backOnly = samplePixel(image, x: 5, y: 54)
        #expect(backOnly.r > 0.5)
        #expect(backOnly.b < 0.5)
    }

    @Test("prepareLayerImage clears soft fringe outside continuous corners")
    func prepareClearsCornerFringe() {
        // Opaque white square — after continuous masking, corner pixels that
        // sit outside the silhouette must become fully transparent.
        let square = makeSolidImage(width: 100, height: 100, rgba: (1, 1, 1, 1))
        let prepared = MultiWindowCompositor.prepareLayerImage(
            square,
            pointSize: CGSize(width: 100, height: 100),
            cornerRadiusPoints: 16,
            insetPoints: 0.75
        )
        #expect(prepared != nil)
        guard let prepared else { return }

        let corner = samplePixel(prepared, x: 1, y: 1)
        #expect(corner.a < 0.05)

        let center = samplePixel(prepared, x: 50, y: 50)
        #expect(center.a > 0.9)
        #expect(center.r > 0.9)
    }

    @Test("composite returns nil for empty layers")
    func compositeEmpty() {
        #expect(MultiWindowCompositor.composite(layers: []) == nil)
    }

    // MARK: - Helpers

    private func makeSolidImage(
        width: Int,
        height: Int,
        rgba: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(
            red: rgba.0, green: rgba.1, blue: rgba.2, alpha: rgba.3
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func samplePixel(
        _ image: CGImage,
        x: Int,
        y: Int
    ) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(
            image,
            in: CGRect(x: -x, y: -y, width: image.width, height: image.height)
        )
        return (
            r: CGFloat(pixel[0]) / 255,
            g: CGFloat(pixel[1]) / 255,
            b: CGFloat(pixel[2]) / 255,
            a: CGFloat(pixel[3]) / 255
        )
    }
}
