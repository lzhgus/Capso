import Testing
import CoreGraphics
@testable import AnnotationKit

@Suite("Arrow head styles")
struct ArrowHeadStyleTests {
    private let width = 200, height = 60

    /// Renders an arrow from (20, 30) to (180, 30) and returns the inked pixels' alpha.
    private func render(_ style: ArrowHeadStyle, lineWidth: CGFloat = 6) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ArrowObject(start: CGPoint(x: 20, y: 30), end: CGPoint(x: 180, y: 30),
                    style: StrokeStyle(color: .black, lineWidth: lineWidth, arrowHead: style)).render(in: ctx)
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }

    /// Inked pixels in the columns `range`.
    private func ink(_ alpha: [UInt8], columns range: Range<Int>) -> Int {
        (0..<height).reduce(0) { sum, row in sum + range.filter { alpha[row * width + $0] > 128 }.count }
    }

    @Test("A filled head puts more ink near the tip than an open one")
    func filledHead() {
        #expect(ink(render(.filled, lineWidth: 2), columns: 150..<180) > ink(render(.standard, lineWidth: 2), columns: 150..<180) + 25)
    }

    @Test("Double arrows have a head at the tail too")
    func doubleHead() {
        #expect(ink(render(.double, lineWidth: 2), columns: 20..<50) > ink(render(.filled, lineWidth: 2), columns: 20..<50) + 50)
    }

    @Test("A tapered shaft is thin at the tail and full near the head")
    func taperedShaft() {
        let tapered = render(.tapered)
        #expect(ink(tapered, columns: 25..<35) < ink(render(.standard), columns: 25..<35) / 2)
        #expect(ink(tapered, columns: 130..<140) >= ink(render(.standard), columns: 130..<140) - 10)
    }
}
