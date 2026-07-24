import AppKit
import XCTest
@testable import Capso
import SharedKit

@MainActor
final class RecordingToolbarShortcutTests: XCTestCase {
    func testReturnStartsVideoRecording() throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }

        let event = try makeReturnEvent(
            modifierFlags: [],
            windowNumber: harness.window.windowNumber
        )

        NSApp.sendEvent(event)
        XCTAssertEqual(harness.recordedFormats(), [.video])
    }

    func testOptionReturnStartsGIFRecording() throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }

        let event = try makeReturnEvent(
            modifierFlags: .option,
            windowNumber: harness.window.windowNumber
        )

        NSApp.sendEvent(event)
        XCTAssertEqual(harness.recordedFormats(), [.gif])
    }

    private func makeHarness() throws -> RecordingToolbarHarness {
        let suiteName = "RecordingToolbarShortcutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = AppSettings(defaults: defaults)
        let screen = try XCTUnwrap(NSScreen.main)
        var recordedFormats: [RecordingFormatChoice] = []

        let window = RecordingToolbarWindow(
            selectionRect: CGRect(x: 100, y: 100, width: 640, height: 480),
            screen: screen,
            settings: settings,
            onRecord: { format, _, _, _, _ in
                recordedFormats.append(format)
            },
            onCameraToggled: { _, _ in true },
            onChangeArea: {},
            onCancel: {},
            onCameraSettingsChanged: {}
        )
        window.show()

        return RecordingToolbarHarness(
            window: window,
            suiteName: suiteName,
            recordedFormats: { recordedFormats }
        )
    }

    private func makeReturnEvent(
        modifierFlags: NSEvent.ModifierFlags,
        windowNumber: Int
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
    }
}

final class CaptureWindowPolicyTests: XCTestCase {
    func testElevatedWindowsUseTheFrozenDisplayCapture() {
        XCTAssertTrue(CaptureCoordinator.shouldUseFrozenWindowCapture(windowLayer: 27))
        XCTAssertFalse(CaptureCoordinator.shouldUseFrozenWindowCapture(windowLayer: 0))
    }
}

@MainActor
private struct RecordingToolbarHarness {
    let window: RecordingToolbarWindow
    let suiteName: String
    let recordedFormats: () -> [RecordingFormatChoice]

    func cleanUp() {
        window.close()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}
