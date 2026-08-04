import CoreGraphics
import Testing
@testable import CaptureKit

@Suite("ScrollStitcher")
struct ScrollStitcherTests {
    @Test("A slightly changing fixed header is not repeated in the stitched image")
    func changingFixedHeaderIsNotRepeated() throws {
        let first = makeFrame(rowsTopToBottom: [
            .red,
            .orange,
            .yellow,
            .green,
            .cyan,
            .blue,
        ])
        let next = makeFrame(
            rowsTopToBottom: [
                .red,
                .green,
                .cyan,
                .blue,
                .purple,
                .white,
            ],
            changedHeaderPixel: true
        )

        let stitcher = ScrollStitcher()
        stitcher.setInitialFrame(first)
        _ = stitcher.stitch(newFrame: next, detectedOffset: 2)

        let result = try #require(stitcher.mergedImage)
        #expect(result.height == 8)
        #expect(rowsTopToBottom(in: result) == [
            .red,
            .orange,
            .yellow,
            .green,
            .cyan,
            .blue,
            .purple,
            .white,
        ])
    }

    private enum RowColor: Equatable {
        case red, orange, yellow, green, cyan, blue, purple, white

        var components: (CGFloat, CGFloat, CGFloat, CGFloat) {
            switch self {
            case .red: (1, 0, 0, 1)
            case .orange: (1, 0.5, 0, 1)
            case .yellow: (1, 1, 0, 1)
            case .green: (0, 1, 0, 1)
            case .cyan: (0, 1, 1, 1)
            case .blue: (0, 0, 1, 1)
            case .purple: (0.5, 0, 1, 1)
            case .white: (1, 1, 1, 1)
            }
        }
    }

    private func makeFrame(
        rowsTopToBottom: [RowColor],
        changedHeaderPixel: Bool = false
    ) -> CGImage {
        let width = 32
        let height = rowsTopToBottom.count
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        for (topRow, color) in rowsTopToBottom.enumerated() {
            let components = color.components
            context.setFillColor(
                red: components.0,
                green: components.1,
                blue: components.2,
                alpha: components.3
            )
            context.fill(CGRect(x: 0, y: height - topRow - 1, width: width, height: 1))
        }

        if changedHeaderPixel {
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: height - 1, width: 1, height: 1))
        }

        return context.makeImage()!
    }

    private func rowsTopToBottom(in image: CGImage) -> [RowColor] {
        (0..<image.height).map { topRow in
            classify(samplePixel(image, x: image.width / 2, y: image.height - topRow - 1))
        }
    }

    private func samplePixel(
        _ image: CGImage,
        x: Int,
        y: Int
    ) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        return (
            CGFloat(pixel[0]) / 255,
            CGFloat(pixel[1]) / 255,
            CGFloat(pixel[2]) / 255
        )
    }

    private func classify(_ pixel: (r: CGFloat, g: CGFloat, b: CGFloat)) -> RowColor {
        let candidates: [RowColor] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .white]
        return candidates.min { lhs, rhs in
            distance(pixel, from: lhs) < distance(pixel, from: rhs)
        }!
    }

    private func distance(
        _ pixel: (r: CGFloat, g: CGFloat, b: CGFloat),
        from color: RowColor
    ) -> CGFloat {
        let components = color.components
        return abs(pixel.r - components.0)
            + abs(pixel.g - components.1)
            + abs(pixel.b - components.2)
    }
}
