import AppKit
import XCTest
import SharedKit
@testable import Capso

@MainActor
final class AnnotationEditorWindowCenteringTests: XCTestCase {
    /// The regression from issue #236: a capture small enough that the
    /// image-derived width falls below the toolbar's intrinsic width. AppKit
    /// applied the hosting view's size a runloop pass *after* the window had
    /// been positioned, widening it rightwards from a fixed origin and
    /// dragging it off-center.
    func testSmallCaptureStaysCenteredAfterAppKitAppliesMinimumSize() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let window = try makeWindow(pixelWidth: 600, pixelHeight: 400, screen: screen)
        defer { window.close() }

        let frameBeforeShow = window.frame
        window.show()
        settleLayout()

        // The regression: AppKit used to widen the window here, from a pinned
        // origin. Whatever we computed has to survive presentation intact.
        assertFrame(window.frame, matches: frameBeforeShow)
        assertPlacedOnScreen(window, on: screen)
        // Guards the premise: the toolbar forced the window wider than the
        // 600px image. Without that growth this test proves nothing.
        XCTAssertGreaterThan(window.frame.width, 600)
    }

    /// A wide Retina capture is sized from the image rather than the toolbar
    /// minimum, and must be converted from pixels to points so it stays inside
    /// the viewport budget instead of overflowing the display.
    func testWideRetinaCaptureIsCenteredAndFitsTheVisibleFrame() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let window = try makeWindow(pixelWidth: 6000, pixelHeight: 1500, screen: screen)
        defer { window.close() }

        // Placement is asserted before presentation: once the window is on
        // screen, macOS occasionally nudges wide windows during app activation
        // (observed as a ~40pt drift), which is unrelated to this sizing path.
        assertPlacedOnScreen(window, on: screen)

        let sizeBeforeShow = window.frame.size
        window.show()
        settleLayout()

        // The SwiftUI tree must not have forced it any wider.
        XCTAssertEqual(window.frame.width, sizeBeforeShow.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, sizeBeforeShow.height, accuracy: 1)
        XCTAssertLessThanOrEqual(
            window.frame.width, screen.visibleFrame.width + 1,
            "6000px capture was not scaled into the viewport: \(window.frame)"
        )
    }

    /// The toolbar's tool row scrolls, so its natural width is a preference the
    /// display can override. Without that, a display narrower than the toolbar
    /// gets a window it cannot fit or center — which is what CI's 1024pt-wide
    /// runner hits.
    func testWindowNeverOutgrowsTheDisplayWidth() throws {
        let screen = try XCTUnwrap(NSScreen.main)

        for pixelWidth in [10, 600, 6000] {
            let window = try makeWindow(pixelWidth: pixelWidth, pixelHeight: 400, screen: screen)
            defer { window.close() }
            window.show()
            settleLayout()

            XCTAssertLessThanOrEqual(
                window.frame.width, screen.visibleFrame.width + 1,
                "\(pixelWidth)px capture produced a window wider than the display: \(window.frame)"
            )
            assertPlacedOnScreen(window, on: screen)
        }
    }

    /// `show()` positions the window once. A window the user has dragged
    /// elsewhere must not be yanked back to center by a later `show()`.
    func testSubsequentShowDoesNotRepositionAMovedWindow() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let window = try makeWindow(pixelWidth: 600, pixelHeight: 400, screen: screen)
        defer { window.close() }

        window.show()
        settleLayout()

        let moved = window.frame.offsetBy(dx: 40, dy: -30)
        window.setFrame(moved, display: false)
        window.show()

        XCTAssertEqual(window.frame.origin.x, moved.origin.x, accuracy: 1)
        XCTAssertEqual(window.frame.origin.y, moved.origin.y, accuracy: 1)
    }

    // MARK: - Helpers

    private func assertFrame(
        _ frame: NSRect,
        matches expected: NSRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(frame.origin.x, expected.origin.x, accuracy: 1, "\(frame) vs \(expected)", file: file, line: line)
        XCTAssertEqual(frame.origin.y, expected.origin.y, accuracy: 1, "\(frame) vs \(expected)", file: file, line: line)
        XCTAssertEqual(frame.width, expected.width, accuracy: 1, "\(frame) vs \(expected)", file: file, line: line)
        XCTAssertEqual(frame.height, expected.height, accuracy: 1, "\(frame) vs \(expected)", file: file, line: line)
    }

    /// Asserts the window is centered on `screen`. An axis that cannot fit —
    /// the toolbar's minimum width exceeds narrow displays, including CI's
    /// 1024pt runner — is pinned to the visible origin instead, which is the
    /// best placement available and what AppKit would clamp to anyway.
    private func assertPlacedOnScreen(
        _ window: AnnotationEditorWindow,
        on screen: NSScreen,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let visible = screen.visibleFrame
        let frame = window.frame

        if frame.width <= visible.width {
            XCTAssertEqual(
                frame.midX, visible.midX, accuracy: 1,
                "Window is horizontally off-center: \(frame) in \(visible)",
                file: file, line: line
            )
        } else {
            XCTAssertEqual(
                frame.minX, visible.minX, accuracy: 1,
                "Oversized window should be pinned to the visible origin: \(frame) in \(visible)",
                file: file, line: line
            )
        }

        if frame.height <= visible.height {
            XCTAssertEqual(
                frame.midY, visible.midY, accuracy: 1,
                "Window is vertically off-center: \(frame) in \(visible)",
                file: file, line: line
            )
        } else {
            XCTAssertEqual(
                frame.minY, visible.minY, accuracy: 1,
                "Oversized window should be pinned to the visible origin: \(frame) in \(visible)",
                file: file, line: line
            )
        }
    }

    /// Lets AppKit apply the hosting view's `contentMinSize`, which happens on
    /// a later runloop pass. Without this the assertions run against a frame
    /// the user never actually sees.
    private func settleLayout() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    private func makeWindow(
        pixelWidth: Int,
        pixelHeight: Int,
        screen: NSScreen
    ) throws -> AnnotationEditorWindow {
        AnnotationEditorWindow(
            image: try makeImage(width: pixelWidth, height: pixelHeight),
            anchorScreen: screen,
            screenshotOutput: ScreenshotOutputOptions(format: .png, quality: 0.85),
            screenshotFilenameTemplate: "Screenshot",
            onSave: { _ in true },
            onCopy: { _ in },
            onPin: { _, _ in },
            onClose: {}
        )
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
