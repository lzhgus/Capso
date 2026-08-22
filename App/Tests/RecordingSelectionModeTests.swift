import AppKit
import XCTest
@testable import Capso
import SharedKit

@MainActor
final class RecordingSelectionModeTests: XCTestCase {
    func testLetterShortcutsMapToEveryRecordingSelectionMode() {
        XCTAssertEqual(CaptureOverlayShortcutAction(keyCode: 0), .selectArea)
        XCTAssertEqual(CaptureOverlayShortcutAction(keyCode: 13), .selectWindow)
        XCTAssertEqual(CaptureOverlayShortcutAction(keyCode: 3), .selectFullScreen)
        XCTAssertEqual(CaptureOverlayShortcutAction(keyCode: 15), .reuseLastArea)
        XCTAssertNil(CaptureOverlayShortcutAction(keyCode: 12))
    }

    func testOverlayRoutesARecordingModeShortcutExactlyOnce() throws {
        let suiteName = "RecordingSelectionModeTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let screen = try XCTUnwrap(NSScreen.main)
        let window = CaptureOverlayWindow(
            screen: screen,
            settings: settings,
            handlesGlobalKeyEvents: true,
            presetsDisabled: true,
            allowsMultiWindowSelection: false
        )
        var requestedActions: [CaptureOverlayShortcutAction] = []
        window.onShortcutAction = { requestedActions.append($0) }

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))

        XCTAssertNil(window.handleLocalKeyEvent(event))
        XCTAssertEqual(requestedActions, [.selectWindow])
    }

    func testOverlayLeavesModifiedLetterShortcutsUntouched() throws {
        let suiteName = "RecordingSelectionModeTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let screen = try XCTUnwrap(NSScreen.main)
        let window = CaptureOverlayWindow(
            screen: screen,
            settings: settings,
            handlesGlobalKeyEvents: true,
            presetsDisabled: true,
            allowsMultiWindowSelection: false
        )
        var requestedActions: [CaptureOverlayShortcutAction] = []
        window.onShortcutAction = { requestedActions.append($0) }
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))

        XCTAssertTrue(window.handleLocalKeyEvent(event) === event)
        XCTAssertTrue(requestedActions.isEmpty)
    }

    func testSpaceTogglesAreaModeToWindowInFocusedHUD() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        var requestedModes: [RecordingSelectionMode] = []
        let window = RecordingSelectionModeWindow(
            screen: screen,
            selectedMode: .area,
            canUseLastArea: false,
            onSelect: { requestedModes.append($0) },
            onCancel: {}
        )
        defer { window.close() }

        window.keyDown(with: try makeKeyEvent(" ", keyCode: 49, windowNumber: window.windowNumber))

        XCTAssertEqual(requestedModes, [.window])
    }

    func testRepeatedSpaceCancelsPendingWindowModeRequest() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        var requestedModes: [RecordingSelectionMode] = []
        let window = RecordingSelectionModeWindow(
            screen: screen,
            selectedMode: .area,
            canUseLastArea: false,
            onSelect: { requestedModes.append($0) },
            onCancel: {}
        )
        defer { window.close() }
        let event = try makeKeyEvent(" ", keyCode: 49, windowNumber: window.windowNumber)

        window.keyDown(with: event)
        window.keyDown(with: event)

        XCTAssertEqual(requestedModes, [.window, .area])
    }

    func testHUDCanRestoreAreaAfterWindowEnumerationFailure() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        var requestedModes: [RecordingSelectionMode] = []
        let window = RecordingSelectionModeWindow(
            screen: screen,
            selectedMode: .area,
            canUseLastArea: false,
            onSelect: { requestedModes.append($0) },
            onCancel: {}
        )
        defer { window.close() }
        let event = try makeKeyEvent(" ", keyCode: 49, windowNumber: window.windowNumber)

        window.keyDown(with: event)
        window.setSelectedMode(.area)
        window.keyDown(with: event)

        XCTAssertEqual(requestedModes, [.window, .window])
    }

    func testWindowEnumerationFailurePreservesTheActiveOverlayMode() {
        XCTAssertEqual(
            RecordingCoordinator.windowEnumerationFallbackMode(activeMode: .area),
            .area
        )
        XCTAssertEqual(
            RecordingCoordinator.windowEnumerationFallbackMode(activeMode: .window),
            .window
        )
    }

    func testSelectedAreaIsRememberedWhenAutomaticReuseIsOff() throws {
        let suiteName = "RecordingSelectionModeTests.\(UUID().uuidString)"
        defer {
            closeRecordingSelectionWindows()
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        let settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        settings.rememberLastRecordingArea = false
        let screen = try XCTUnwrap(NSScreen.main)
        let rect = CGRect(x: 80, y: 90, width: 640, height: 360)
        let coordinator = RecordingCoordinator(settings: settings)

        coordinator.startRecordingFlow(withSelectedArea: rect, screen: screen)

        XCTAssertEqual(
            settings.lastRecordingArea,
            .area(rect: rect, screenID: screen.displayID)
        )
    }

    func testLastAreaShortcutWorksWithoutAutomaticReuse() async throws {
        let suiteName = "RecordingSelectionModeTests.\(UUID().uuidString)"
        defer {
            closeRecordingSelectionWindows()
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        let settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let screen = try XCTUnwrap(NSScreen.main)
        settings.rememberLastRecordingArea = false
        settings.lastRecordingArea = .area(
            rect: CGRect(x: 100, y: 120, width: 640, height: 360),
            screenID: screen.displayID
        )
        let coordinator = RecordingCoordinator(settings: settings)

        coordinator.startRecordingFlow()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(NSApp.windows.contains { $0 is RecordingToolbarWindow && $0.isVisible })
        let modeWindow = try XCTUnwrap(
            NSApp.windows.first { $0 is RecordingSelectionModeWindow && $0.isVisible }
                as? RecordingSelectionModeWindow
        )
        modeWindow.keyDown(with: try makeKeyEvent("r", keyCode: 15, windowNumber: modeWindow.windowNumber))

        XCTAssertTrue(NSApp.windows.contains { $0 is RecordingToolbarWindow && $0.isVisible })
    }

    func testFullScreenShortcutShowsRecordingToolbar() async throws {
        let suiteName = "RecordingSelectionModeTests.\(UUID().uuidString)"
        defer {
            closeRecordingSelectionWindows()
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        let settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let coordinator = RecordingCoordinator(settings: settings)

        coordinator.startRecordingFlow()
        try await Task.sleep(for: .milliseconds(250))
        let modeWindow = try XCTUnwrap(
            NSApp.windows.first { $0 is RecordingSelectionModeWindow && $0.isVisible }
                as? RecordingSelectionModeWindow
        )
        modeWindow.keyDown(with: try makeKeyEvent("f", keyCode: 3, windowNumber: modeWindow.windowNumber))

        XCTAssertTrue(NSApp.windows.contains { $0 is RecordingToolbarWindow && $0.isVisible })
    }

    func testDirectFullScreenRecordingSkipsSelectionAndShowsToolbar() async throws {
        let suiteName = "RecordingSelectionModeTests.\(UUID().uuidString)"
        defer {
            closeRecordingSelectionWindows()
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        let settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let coordinator = RecordingCoordinator(settings: settings)

        coordinator.startFullScreenRecordingFlow()
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertFalse(NSApp.windows.contains { $0 is RecordingSelectionModeWindow && $0.isVisible })
        XCTAssertFalse(NSApp.windows.contains { $0 is CaptureOverlayWindow && $0.isVisible })
        XCTAssertTrue(NSApp.windows.contains { $0 is RecordingToolbarWindow && $0.isVisible })
    }

    private func makeKeyEvent(_ characters: String, keyCode: UInt16, windowNumber: Int) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func closeRecordingSelectionWindows() {
        for window in NSApp.windows where window is CaptureOverlayWindow
            || window is RecordingSelectionModeWindow
            || window is RecordingToolbarWindow {
            window.close()
        }
    }
}
