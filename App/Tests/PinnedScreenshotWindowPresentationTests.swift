import AppKit
import SharedKit
import XCTest

@testable import Capso

@MainActor
final class PinnedScreenshotWindowPresentationTests: XCTestCase {
    func testClipboardPinUsesNonactivatingPanel() throws {
        let window = PinnedScreenshotWindow(
            image: try makeImage(),
            anchorRect: nil,
            activatesApp: false,
            onCopy: {},
            onSave: {},
            onDidClose: { _ in }
        )
        defer { window.close() }

        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(window.activatesAppWhenShown)
    }

    func testExistingPinDefaultsToActivatingWindow() throws {
        let window = PinnedScreenshotWindow(
            image: try makeImage(),
            anchorRect: nil,
            onCopy: {},
            onSave: {},
            onDidClose: { _ in }
        )
        defer { window.close() }

        XCTAssertFalse(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(window.activatesAppWhenShown)
    }

    func testCoordinatorRoutesClipboardContentToANonactivatingPin() throws {
        let suiteName = "PinnedScreenshotWindowPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let coordinator = CaptureCoordinator(settings: AppSettings(defaults: defaults))
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PinnedScreenshotWindowPresentationTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        pasteboard.setString("Pinned clipboard text", forType: .string)
        let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))

        coordinator.pinFromClipboard(pasteboard: pasteboard)

        let window = try XCTUnwrap(NSApp.windows.first {
            $0 is PinnedScreenshotWindow && !existingWindows.contains(ObjectIdentifier($0))
        } as? PinnedScreenshotWindow)
        defer { window.close() }
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(window.activatesAppWhenShown)
    }

    private func makeImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 12,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 48,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }
}
