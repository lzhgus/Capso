import AppKit
import CaptureKit
import SharedKit
import SwiftUI
import XCTest
@testable import Capso

@MainActor
final class QuickAccessWindowPresentationTests: XCTestCase {
    func testLargeCaptureUsesBoundedThumbnailAndPreservesOriginalImage() throws {
        let original = try makeImage(width: 4096, height: 2048)
        let (window, suiteName) = try makeWindow(autoClose: false, image: original)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let view = try XCTUnwrap(window.contentView as? NSHostingView<QuickAccessView>).rootView
        let thumbnail = try XCTUnwrap(view.thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let scale = max(2, window.targetScreen.backingScaleFactor)
        XCTAssertLessThanOrEqual(thumbnail.width, Int(268 * scale))
        XCTAssertLessThanOrEqual(thumbnail.height, Int(142 * scale))
        XCTAssertEqual(view.captureImage.width, 4096)
        XCTAssertEqual(view.captureImage.height, 2048)
    }

    func testPanoramicAndPortraitThumbnailsCropBeforeDownsampling() throws {
        for (width, height) in [(4096, 64), (64, 4096)] {
            let original = try makeImage(width: width, height: height)
            let (window, suiteName) = try makeWindow(autoClose: false, image: original)
            defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
            let view = try XCTUnwrap(window.contentView as? NSHostingView<QuickAccessView>).rootView
            // The display texture must match the card, rather than stretching
            // a downsampled panorama's few remaining rows to fill its height.
            XCTAssertEqual(view.thumbnail.size.width / view.thumbnail.size.height, 268.0 / 142.0, accuracy: 0.04)
            XCTAssertEqual(view.captureImage.width, width)
            XCTAssertEqual(view.captureImage.height, height)
        }
    }

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

    func testEvictionDuringEntranceStaysHiddenAndDoesNotRestartAutoClose() throws {
        let (window, defaultsSuiteName) = try makeWindow(autoClose: true, interval: 1)
        defer {
            window.orderOut(nil)
            UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        }
        var closeCount = 0
        window.onClose = { closeCount += 1 }

        window.show(from: NSRect(x: 100, y: 100, width: 640, height: 480))
        window.slideOffLeftAndClose()
        settleRunLoop(for: 0.8)

        XCTAssertFalse(window.isVisible)
        settleRunLoop(for: 1.2)
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(closeCount, 0)
    }

    func testRapidCapturesKeepOnlyFiveVisibleAndDismissiblePreviews() throws {
        let suiteName = "QuickAccessWindowPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = AppSettings(defaults: defaults)
        settings.quickAccessAutoClose = false
        let coordinator = CaptureCoordinator(settings: settings)
        let result = CaptureResult(
            image: try makeImage(),
            mode: .area,
            captureRect: CGRect(x: 100, y: 100, width: 640, height: 480)
        )
        var windows: [QuickAccessWindow] = []
        defer {
            windows.forEach { $0.orderOut(nil) }
            defaults.removePersistentDomain(forName: suiteName)
        }

        for _ in 0..<6 {
            windows.append(coordinator.showQuickAccess(
                for: result,
                entryID: UUID(),
                autoUpload: false,
                animationSourceFrame: result.captureRect
            ))
        }
        settleRunLoop(for: 0.8)

        XCTAssertFalse(windows[0].isVisible)
        XCTAssertEqual(windows.filter(\.isVisible).count, 5)

        windows.forEach { $0.onClose?() }
        settleRunLoop(for: 0.8)
        XCTAssertTrue(windows.allSatisfy { !$0.isVisible })
    }

    func testCloseAllDuringEntranceStaysClosed() throws {
        let suiteName = "QuickAccessWindowPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = AppSettings(defaults: defaults)
        settings.quickAccessAutoClose = false
        let coordinator = CaptureCoordinator(settings: settings)
        defer {
            coordinator.closeAllQuickAccess()
            settleRunLoop(for: 0.4)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let result = CaptureResult(
            image: try makeImage(), mode: .area,
            captureRect: CGRect(x: 100, y: 100, width: 640, height: 480)
        )
        let window = coordinator.showQuickAccess(
            for: result, entryID: UUID(), autoUpload: false,
            animationSourceFrame: result.captureRect
        )

        coordinator.closeAllQuickAccess()
        settleRunLoop(for: 0.8)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(coordinator.hasQuickAccess)
    }

    func testReopenDuringCloseAnimationKeepsTheNewPreview() throws {
        let suiteName = "QuickAccessWindowPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = AppSettings(defaults: defaults)
        settings.quickAccessAutoClose = false
        let coordinator = CaptureCoordinator(settings: settings)
        defer {
            coordinator.closeAllQuickAccess()
            settleRunLoop(for: 0.4)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let result = CaptureResult(
            image: try makeImage(), mode: .area,
            captureRect: CGRect(x: 100, y: 100, width: 640, height: 480)
        )
        let window = coordinator.showQuickAccess(
            for: result, entryID: UUID(), autoUpload: false,
            animationSourceFrame: result.captureRect
        )

        window.onClose?()
        XCTAssertTrue(coordinator.canReopenQuickAccess)
        coordinator.reopenQuickAccess()
        settleRunLoop(for: 0.8)

        XCTAssertTrue(coordinator.hasQuickAccess)
        XCTAssertFalse(window.isVisible, "The cancelled entrance must not restore the old card")
    }

    func testDragEndingAfterCloseDoesNotRestorePanelOrRestartAutoDismiss() throws {
        let (window, suiteName) = try makeWindow(autoClose: true, interval: 1)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        window.show()
        settleRunLoop(for: 0.6)
        var closeCount = 0
        window.onClose = { closeCount += 1 }
        let hostingView = try XCTUnwrap(window.contentView as? NSHostingView<QuickAccessView>)
        hostingView.rootView.onDragStarted()
        window.close()
        hostingView.rootView.onDragEnded(false)
        hostingView.rootView.onDragEnded(true)
        settleRunLoop(for: 1.2)

        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertEqual(closeCount, 0)
    }

    func testClosingDuringEntranceDoesNotReappearAtAnimationCompletion() throws {
        let (window, suiteName) = try makeWindow(autoClose: false)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        window.show(from: NSRect(x: 100, y: 100, width: 800, height: 600))
        window.close()
        settleRunLoop(for: 0.7)
        XCTAssertFalse(window.isVisible)
    }

    func testCloseScalesTowardAnchoredEdgeWithoutLeavingTargetScreen() throws {
        for position in QuickAccessPosition.allCases {
            let (window, suiteName) = try makeWindow(autoClose: false, position: position)
            defer {
                window.orderOut(nil)
                UserDefaults.standard.removePersistentDomain(forName: suiteName)
            }

            window.show()
            settleRunLoop(for: 0.6)
            let startFrame = window.frame
            let screenFrame = window.targetScreen.frame
            let contentLayer = try XCTUnwrap(window.contentView?.layer)

            window.close()
            settleRunLoop(for: 0.5)

            XCTAssertFalse(window.isVisible)
            XCTAssertGreaterThanOrEqual(window.frame.minX, screenFrame.minX)
            XCTAssertLessThanOrEqual(window.frame.maxX, screenFrame.maxX)
            XCTAssertGreaterThanOrEqual(window.frame.minY, screenFrame.minY)
            XCTAssertLessThanOrEqual(window.frame.maxY, screenFrame.maxY)
            switch position {
            case .bottomLeft:
                XCTAssertLessThan(window.frame.minX, startFrame.minX)
                XCTAssertLessThan(window.frame.maxX, startFrame.maxX)
                XCTAssertLessThan(contentLayer.transform.m11, 1)
                XCTAssertEqual(window.frame.minY, startFrame.minY)
            case .bottomRight:
                XCTAssertGreaterThan(window.frame.minX, startFrame.minX)
                XCTAssertGreaterThan(window.frame.maxX, startFrame.maxX)
                XCTAssertLessThan(contentLayer.transform.m11, 1)
                XCTAssertEqual(window.frame.minY, startFrame.minY)
            case .centerScreen:
                XCTAssertLessThan(window.frame.minY, startFrame.minY)
                XCTAssertLessThan(window.frame.maxY, startFrame.maxY)
                XCTAssertLessThan(contentLayer.transform.m22, 1)
                XCTAssertEqual(window.frame.minX, startFrame.minX)
            }
        }
    }

    func testCloseReturnsDraggedCardEntirelyToTargetScreen() throws {
        for position in QuickAccessPosition.allCases {
            let (window, suiteName) = try makeWindow(autoClose: false, position: position)
            defer {
                window.orderOut(nil)
                UserDefaults.standard.removePersistentDomain(forName: suiteName)
            }

            window.show()
            settleRunLoop(for: 0.6)
            let screenFrame = window.targetScreen.frame
            let draggedFrame = NSRect(
                x: screenFrame.maxX - window.frame.width / 2,
                y: screenFrame.maxY - window.frame.height / 2,
                width: window.frame.width,
                height: window.frame.height
            )
            window.setFrame(draggedFrame, display: false)

            window.close()
            settleRunLoop(for: 0.5)

            XCTAssertGreaterThanOrEqual(window.frame.minX, screenFrame.minX)
            XCTAssertLessThanOrEqual(window.frame.maxX, screenFrame.maxX)
            XCTAssertGreaterThanOrEqual(window.frame.minY, screenFrame.minY)
            XCTAssertLessThanOrEqual(window.frame.maxY, screenFrame.maxY)
        }
    }

    private func makeWindow(
        autoClose: Bool,
        interval: Int = 5,
        position: QuickAccessPosition = .bottomRight,
        image: CGImage? = nil
    ) throws -> (QuickAccessWindow, String) {
        let suiteName = "QuickAccessWindowPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        settings.quickAccessAutoClose = autoClose
        settings.quickAccessAutoCloseInterval = interval
        settings.quickAccessPosition = position

        return (QuickAccessWindow(
            result: CaptureResult(
                image: try image ?? makeImage(),
                mode: .area,
                captureRect: CGRect(x: 0, y: 0, width: 8, height: 6)
            ),
            settings: settings,
            screen: try XCTUnwrap(NSScreen.main),
            shareCoordinator: nil,
            autoUpload: false
        ), suiteName)
    }

    private func makeImage(width: Int = 8, height: Int = 6) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func settleRunLoop(for interval: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }
}

@MainActor
final class HistoryWindowShortcutToggleTests: XCTestCase {
    func testToggleShowsHidesAndShowsTheSameHistoryWindow() throws {
        let suiteName = "HistoryWindowShortcutToggleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let coordinator = HistoryCoordinator(settings: AppSettings(defaults: defaults))
        defer {
            if coordinator.isWindowVisibleForTesting {
                coordinator.toggleWindow()
            }
            defaults.removePersistentDomain(forName: suiteName)
        }

        coordinator.toggleWindow()
        XCTAssertTrue(coordinator.isWindowVisibleForTesting)

        coordinator.toggleWindow()
        XCTAssertFalse(coordinator.isWindowVisibleForTesting)

        coordinator.toggleWindow()
        XCTAssertTrue(coordinator.isWindowVisibleForTesting)
    }
}
