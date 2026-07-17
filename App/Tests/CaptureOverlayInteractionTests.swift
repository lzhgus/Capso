import AppKit
import XCTest
@testable import Capso
import SharedKit

@MainActor
final class CaptureOverlayInteractionTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var settings: AppSettings!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "CaptureOverlayInteractionTests.\(UUID().uuidString)"
        settings = AppSettings(defaults: UserDefaults(suiteName: defaultsSuiteName)!)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        settings = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testEscapeEventClearsMultiSelectionWithoutCancellingOtherDisplayOverlay() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let firstWindow = CaptureOverlayWindow(screen: screen, settings: settings)
        let secondWindow = CaptureOverlayWindow(screen: screen, settings: settings)
        let firstView = try XCTUnwrap(firstWindow.contentView as? CaptureOverlayView)
        let secondView = try XCTUnwrap(secondWindow.contentView as? CaptureOverlayView)

        firstView.setMode(.windowSelection([]))
        secondView.setMode(.windowSelection([]))
        NotificationCenter.default.post(
            name: .multiWindowSelectionChanged,
            object: self,
            userInfo: ["windowIDs": [NSNumber(value: CGWindowID(42))]]
        )

        var cancellationCount = 0
        firstWindow.onCancelled = { cancellationCount += 1 }
        secondWindow.onCancelled = { cancellationCount += 1 }

        let firstEscape = try makeEscapeEvent(windowNumber: firstWindow.windowNumber)
        XCTAssertNil(firstWindow.handleLocalKeyEvent(firstEscape))
        XCTAssertTrue(secondWindow.handleLocalKeyEvent(firstEscape) === firstEscape)
        XCTAssertEqual(cancellationCount, 0)

        let secondEscape = try makeEscapeEvent(windowNumber: secondWindow.windowNumber)
        XCTAssertNil(secondWindow.handleLocalKeyEvent(secondEscape))
        XCTAssertEqual(cancellationCount, 1)
    }

    func testRecordingWindowSelectionTreatsShiftClickAsSingleSelection() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let hostWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = CaptureOverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            settings: settings,
            safeAreaTopInset: 0,
            presetsDisabled: true,
            allowsMultiWindowSelection: false
        )
        hostWindow.contentView = view
        view.setMode(.windowSelection([]))

        var selectedWindowID: CGWindowID?
        view.onWindowSelected = { selectedWindowID = $0 }
        view.handleWindowClick(42, modifierFlags: .shift)

        XCTAssertEqual(selectedWindowID, 42)
        XCTAssertFalse(view.handleEscapeKey(), "Shift-click must not leave recording in multi-select state")
    }

    private func makeEscapeEvent(windowNumber: Int) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        ))
    }
}
