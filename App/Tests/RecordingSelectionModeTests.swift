import AppKit
import XCTest
@testable import Capso
import SharedKit

@MainActor
final class RecordingSelectionModeTests: XCTestCase {
    func testLetterShortcutsMapToEveryRecordingSelectionMode() {
        XCTAssertEqual(RecordingSelectionMode(keyCode: 0), .area)
        XCTAssertEqual(RecordingSelectionMode(keyCode: 13), .window)
        XCTAssertEqual(RecordingSelectionMode(keyCode: 3), .fullScreen)
        XCTAssertEqual(RecordingSelectionMode(keyCode: 15), .lastArea)
        XCTAssertNil(RecordingSelectionMode(keyCode: 12))
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
        var requestedModes: [RecordingSelectionMode] = []
        window.onRecordingModeRequested = { requestedModes.append($0) }

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
        XCTAssertEqual(requestedModes, [.window])
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
        var requestedModes: [RecordingSelectionMode] = []
        window.onRecordingModeRequested = { requestedModes.append($0) }
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
        XCTAssertTrue(requestedModes.isEmpty)
    }
}
