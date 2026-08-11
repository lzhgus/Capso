import AppKit
import CaptureKit
import SharedKit
import XCTest
@testable import Capso

@MainActor
final class QuickAccessWindowPresentationTests: XCTestCase {
    func testWindowUsesNonactivatingCrossSpaceOverlayConfiguration() throws {
        let (window, defaultsSuiteName) = try makeWindow(autoClose: false)
        defer {
            window.orderOut(nil)
            UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        }

        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(window.level, .floating)
        XCTAssertFalse(window.hidesOnDeactivate)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    func testShowPresentsVisibleKeyWindow() throws {
        let (window, defaultsSuiteName) = try makeWindow(autoClose: false)
        defer {
            window.orderOut(nil)
            UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        }

        window.show()
        settleRunLoop(for: 0.4)

        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window.isKeyWindow)
        settleRunLoop(for: 0.3)
        XCTAssertTrue(window.isVisible)
    }

    func testAutoCloseCallbackFiresOnlyAfterConfiguredInterval() throws {
        let (window, defaultsSuiteName) = try makeWindow(autoClose: true, interval: 1)
        defer {
            window.orderOut(nil)
            UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        }
        var closeCount = 0
        window.onClose = { closeCount += 1 }

        window.show()
        settleRunLoop(for: 0.4)

        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(closeCount, 0)

        settleRunLoop(for: 0.8)

        XCTAssertEqual(closeCount, 1)
    }

    private func makeWindow(
        autoClose: Bool,
        interval: Int = 5
    ) throws -> (QuickAccessWindow, String) {
        let suiteName = "QuickAccessWindowPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        settings.quickAccessAutoClose = autoClose
        settings.quickAccessAutoCloseInterval = interval

        return (QuickAccessWindow(
            result: CaptureResult(
                image: try makeImage(),
                mode: .area,
                captureRect: CGRect(x: 0, y: 0, width: 8, height: 6)
            ),
            settings: settings,
            screen: try XCTUnwrap(NSScreen.main),
            shareCoordinator: nil,
            autoUpload: false
        ), suiteName)
    }

    private func makeImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 8,
            height: 6,
            bitsPerComponent: 8,
            bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        return try XCTUnwrap(context.makeImage())
    }

    private func settleRunLoop(for interval: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }
}
