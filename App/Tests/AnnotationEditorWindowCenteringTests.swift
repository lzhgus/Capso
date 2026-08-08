import AppKit
import XCTest
import SharedKit
@testable import Capso

@MainActor
final class AnnotationEditorWindowCenteringTests: XCTestCase {
    func testShowCentersWindowOnAnchorScreenVisibleFrame() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        // Simulate a Retina area capture: 2× pixels for a modest point size.
        let image = try makeImage(width: 1600, height: 400)

        let window = AnnotationEditorWindow(
            image: image,
            anchorScreen: screen,
            screenshotOutputPreset: .losslessPNG,
            screenshotFilenameTemplate: "Screenshot",
            onSave: { _ in true },
            onCopy: { _ in },
            onPin: { _, _ in },
            onClose: {}
        )
        defer { window.close() }

        window.show()

        let contentSize = AnnotationEditorWindowGeometry.contentSize(
            imagePixelSize: CGSize(width: 1600, height: 400),
            backingScaleFactor: screen.backingScaleFactor,
            visibleSize: screen.visibleFrame.size,
            chromeHeight: 110
        )
        let style: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]
        let frameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: style
        ).size
        let expectedFrame = AnnotationEditorWindowGeometry.centeredFrame(
            size: frameSize,
            in: screen.visibleFrame
        )

        XCTAssertEqual(window.frame.origin.x, expectedFrame.origin.x, accuracy: 1)
        XCTAssertEqual(window.frame.origin.y, expectedFrame.origin.y, accuracy: 1)
        XCTAssertEqual(window.frame.width, expectedFrame.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, expectedFrame.height, accuracy: 1)
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
