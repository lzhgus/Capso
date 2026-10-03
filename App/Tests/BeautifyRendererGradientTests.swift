import AppKit
import SwiftUI
import XCTest
@testable import Capso

@MainActor
final class BeautifyRendererGradientTests: XCTestCase {
    private func makeSolidImage(size: Int, red: CGFloat, green: CGFloat, blue: CGFloat) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return try XCTUnwrap(context.makeImage())
    }

    /// Reads one pixel as sRGB 0...1 components. Row 0 is the top of the image.
    private func pixel(in image: CGImage, x: Int, y: Int) throws -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &data,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // Draw the image offset so that (x, y) lands on the single output pixel.
        // CG contexts are bottom-left; image row `y` from the top is at
        // height - 1 - y from the bottom.
        let flippedY = image.height - 1 - y
        context.draw(image, in: CGRect(x: -x, y: -flippedY, width: image.width, height: image.height))
        return (CGFloat(data[0]) / 255, CGFloat(data[1]) / 255, CGFloat(data[2]) / 255)
    }

    private func assertColor(
        _ actual: (r: CGFloat, g: CGFloat, b: CGFloat),
        matches expected: NSColor,
        tolerance: CGFloat = 0.04,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let e = try XCTUnwrap(expected.usingColorSpace(.sRGB))
        XCTAssertEqual(actual.r, e.redComponent, accuracy: tolerance, "red", file: file, line: line)
        XCTAssertEqual(actual.g, e.greenComponent, accuracy: tolerance, "green", file: file, line: line)
        XCTAssertEqual(actual.b, e.blueComponent, accuracy: tolerance, "blue", file: file, line: line)
    }

    func testGradientFillsPaddingFromTopLeadingToBottomTrailing() throws {
        let source = try makeSolidImage(size: 4, red: 1, green: 0, blue: 0)
        var settings = BeautifySettings()
        settings.isEnabled = true
        settings.backgroundStyle = .gradient
        settings.selectGradientPreset(.dusk)
        settings.padding = 20
        settings.cornerRadius = 0
        settings.shadowEnabled = false

        let output = try XCTUnwrap(BeautifyRenderer.render(image: source, settings: settings))

        XCTAssertEqual(output.width, 44)
        XCTAssertEqual(output.height, 44)

        // Corners of the padding carry the preset's end colours.
        XCTAssertEqual(settings.gradientAngle, 135)
        try assertColor(try pixel(in: output, x: 0, y: 0), matches: BeautifyGradientPreset.dusk.stops[0])
        try assertColor(try pixel(in: output, x: 43, y: 43), matches: BeautifyGradientPreset.dusk.stops[1])

        // The screenshot itself is drawn on top of the gradient. Loose bounds:
        // the renderer works in device RGB, so exact sRGB values shift a little.
        let center = try pixel(in: output, x: 22, y: 22)
        XCTAssertGreaterThan(center.r, 0.9)
        XCTAssertLessThan(center.g, 0.2)
        XCTAssertLessThan(center.b, 0.2)
    }

    func testCustomGradientAtNinetyDegreesRunsLeftToRight() throws {
        let source = try makeSolidImage(size: 4, red: 0, green: 0, blue: 1)
        var settings = BeautifySettings()
        settings.isEnabled = true
        settings.backgroundStyle = .gradient
        settings.gradientPreset = nil
        settings.gradientCustomStart = Color(red: 1, green: 0, blue: 0)
        settings.gradientCustomEnd = Color(red: 0, green: 1, blue: 0)
        settings.gradientAngle = 90
        settings.padding = 20
        settings.cornerRadius = 0
        settings.shadowEnabled = false

        let output = try XCTUnwrap(BeautifyRenderer.render(image: source, settings: settings))

        // Left edge is the start colour on every row, right edge the end colour.
        let left = try pixel(in: output, x: 0, y: 40)
        let right = try pixel(in: output, x: 43, y: 3)
        XCTAssertGreaterThan(left.r, 0.9)
        XCTAssertLessThan(left.g, 0.15)
        XCTAssertLessThan(right.r, 0.15)
        XCTAssertGreaterThan(right.g, 0.9)
    }

    func testEveryPresetHasDistinctStops() {
        for preset in BeautifyGradientPreset.allCases {
            XCTAssertGreaterThanOrEqual(preset.stops.count, 2, "\(preset)")
            XCTAssertNotEqual(preset.stops.first, preset.stops.last, "\(preset) should be a real gradient, not a solid")
        }
        XCTAssertEqual(
            Set(BeautifyGradientPreset.vivid + BeautifyGradientPreset.muted),
            Set(BeautifyGradientPreset.allCases),
            "every preset must be in exactly one panel row"
        )
    }

    func testGeometryReachesCornersOnDiagonalAndEdgesOnAxis() {
        let diagonal = BeautifyGradientGeometry.unitPoints(angle: 135)
        XCTAssertEqual(diagonal.start.x, 0, accuracy: 0.001)
        XCTAssertEqual(diagonal.start.y, 0, accuracy: 0.001)
        XCTAssertEqual(diagonal.end.x, 1, accuracy: 0.001)
        XCTAssertEqual(diagonal.end.y, 1, accuracy: 0.001)

        let vertical = BeautifyGradientGeometry.unitPoints(angle: 180)
        XCTAssertEqual(vertical.start.y, 0, accuracy: 0.001)
        XCTAssertEqual(vertical.end.y, 1, accuracy: 0.001)
        XCTAssertEqual(vertical.start.x, 0.5, accuracy: 0.001)
    }
}
