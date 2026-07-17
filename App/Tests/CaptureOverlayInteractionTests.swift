import AppKit
import XCTest
@testable import Capso
import SharedKit

@MainActor
final class CaptureOverlayInteractionTests: XCTestCase {
    func testEscapeEventClearsMultiSelectionWithoutCancellingOtherDisplayOverlay() throws {
        let (settings, defaultsSuiteName) = makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }

        let screen = try XCTUnwrap(NSScreen.main)
        let firstWindow = CaptureOverlayWindow(
            screen: screen,
            settings: settings,
            handlesGlobalKeyEvents: true
        )
        let secondWindow = CaptureOverlayWindow(
            screen: screen,
            settings: settings,
            handlesGlobalKeyEvents: false
        )
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

    func testGlobalEscapeUsesOneOwnerWhenNoOverlayIsKey() throws {
        let (settings, defaultsSuiteName) = makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }

        let screen = try XCTUnwrap(NSScreen.main)
        let firstWindow = CaptureOverlayWindow(
            screen: screen,
            settings: settings,
            handlesGlobalKeyEvents: true
        )
        let secondWindow = CaptureOverlayWindow(
            screen: screen,
            settings: settings,
            handlesGlobalKeyEvents: false
        )
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

        XCTAssertFalse(firstWindow.isKeyWindow)
        XCTAssertFalse(secondWindow.isKeyWindow)

        let escape = try makeEscapeEvent(windowNumber: 0)
        firstWindow.handleGlobalKeyEvent(escape)
        secondWindow.handleGlobalKeyEvent(escape)
        XCTAssertEqual(cancellationCount, 0)

        firstWindow.handleGlobalKeyEvent(escape)
        secondWindow.handleGlobalKeyEvent(escape)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testGlobalShiftReleaseConfirmsSelectionWhenNoOverlayIsKey() throws {
        let (settings, defaultsSuiteName) = makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }

        let screen = try XCTUnwrap(NSScreen.main)
        let firstWindow = CaptureOverlayWindow(
            screen: screen,
            settings: settings,
            handlesGlobalKeyEvents: true
        )
        let secondWindow = CaptureOverlayWindow(
            screen: screen,
            settings: settings,
            handlesGlobalKeyEvents: false
        )
        let firstView = try XCTUnwrap(firstWindow.contentView as? CaptureOverlayView)
        let secondView = try XCTUnwrap(secondWindow.contentView as? CaptureOverlayView)

        firstView.setMode(.windowSelection([]))
        secondView.setMode(.windowSelection([]))
        NotificationCenter.default.post(
            name: .multiWindowSelectionChanged,
            object: self,
            userInfo: [
                "windowIDs": [
                    NSNumber(value: CGWindowID(42)),
                    NSNumber(value: CGWindowID(43))
                ]
            ]
        )

        var capturedSelections: [[CGWindowID]] = []
        firstWindow.onWindowsSelected = { capturedSelections.append($0) }
        secondWindow.onWindowsSelected = { capturedSelections.append($0) }

        XCTAssertFalse(firstWindow.isKeyWindow)
        XCTAssertFalse(secondWindow.isKeyWindow)

        let commandChanged = try makeFlagsChangedEvent(modifierFlags: .command, keyCode: 55)
        firstWindow.handleGlobalFlagsChanged(commandChanged)
        secondWindow.handleGlobalFlagsChanged(commandChanged)
        XCTAssertTrue(capturedSelections.isEmpty)

        let shiftReleased = try makeFlagsChangedEvent(modifierFlags: [])
        firstWindow.handleGlobalFlagsChanged(shiftReleased)
        secondWindow.handleGlobalFlagsChanged(shiftReleased)

        XCTAssertEqual(capturedSelections, [[42, 43]])
    }

    func testRecordingWindowSelectionTreatsShiftClickAsSingleSelection() throws {
        let (settings, defaultsSuiteName) = makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }

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

    func testSingleShiftSelectionUsesSingleWindowCallback() throws {
        let (settings, defaultsSuiteName) = makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }

        let view = CaptureOverlayView(
            frame: NSRect(origin: .zero, size: NSSize(width: 100, height: 100)),
            settings: settings,
            safeAreaTopInset: 0
        )
        view.setMode(.windowSelection([]))

        var selectedWindowID: CGWindowID?
        var selectedWindowIDs: [CGWindowID]?
        view.onWindowSelected = { selectedWindowID = $0 }
        view.onWindowsSelected = { selectedWindowIDs = $0 }

        view.handleWindowClick(42, modifierFlags: .shift)
        view.handleFlagsChanged(try makeFlagsChangedEvent(modifierFlags: []))

        XCTAssertEqual(selectedWindowID, 42)
        XCTAssertNil(selectedWindowIDs)
    }

    private func makeSettings() -> (AppSettings, String) {
        let suiteName = "CaptureOverlayInteractionTests.\(UUID().uuidString)"
        return (AppSettings(defaults: UserDefaults(suiteName: suiteName)!), suiteName)
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

    private func makeFlagsChangedEvent(
        modifierFlags: NSEvent.ModifierFlags,
        keyCode: UInt16 = 56
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
