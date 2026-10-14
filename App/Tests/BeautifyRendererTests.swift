import AppKit
import SwiftUI
import XCTest
@testable import Capso

final class BeautifyRendererTests: XCTestCase {
    func testTransparentImageCornersShowTheBackground() throws {
        // A window capture: opaque content with its own transparent rounded corners,
        // more rounded than the Beautify corner radius.
        let size = 200
        let window = try XCTUnwrap(Self.context(width: size, height: size))
        window.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerWidth: 40, cornerHeight: 40, transform: nil))
        window.clip()
        window.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        window.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let image = try XCTUnwrap(window.makeImage())

        var settings = BeautifySettings()
        settings.isEnabled = true
        settings.backgroundColor = .black
        settings.padding = 20
        settings.cornerRadius = 8
        settings.shadowEnabled = true
        let output = try XCTUnwrap(BeautifyRenderer.render(image: image, settings: settings))

        let rep = NSBitmapImageRep(cgImage: output)
        let inset = Int(settings.outerInset)
        // Inside the 8 px Beautify corner but outside the window's own 40 px corner.
        let corner = try XCTUnwrap(rep.colorAt(x: inset + 4, y: inset + 4)?.usingColorSpace(.deviceRGB))
        XCTAssertLessThan(corner.redComponent + corner.greenComponent + corner.blueComponent, 0.3, "\(corner)")

        let center = try XCTUnwrap(rep.colorAt(x: inset + size / 2, y: inset + size / 2)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(center.redComponent, 0.9)
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }
}
