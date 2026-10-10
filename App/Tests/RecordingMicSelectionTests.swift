import XCTest
@testable import Capso

final class RecordingMicSelectionTests: XCTestCase {
    func testDisabledStaysDisabled() {
        let selection = RecordingMicSelection.restored(
            enabled: false,
            storedDeviceID: "usb-mic",
            availableDeviceIDs: ["built-in", "usb-mic"],
            defaultDeviceID: "built-in"
        )
        XCTAssertEqual(selection, RecordingMicSelection(enabled: false, deviceID: nil))
    }

    func testRememberedDeviceIsRestoredWhenConnected() {
        let selection = RecordingMicSelection.restored(
            enabled: true,
            storedDeviceID: "usb-mic",
            availableDeviceIDs: ["built-in", "usb-mic"],
            defaultDeviceID: "built-in"
        )
        XCTAssertEqual(selection, RecordingMicSelection(enabled: true, deviceID: "usb-mic"))
    }

    func testMissingDeviceFallsBackToSystemDefault() {
        let selection = RecordingMicSelection.restored(
            enabled: true,
            storedDeviceID: "unplugged-mic",
            availableDeviceIDs: ["built-in"],
            defaultDeviceID: "built-in"
        )
        XCTAssertEqual(selection, RecordingMicSelection(enabled: true, deviceID: "built-in"))
    }

    func testMissingDeviceWithoutKnownDefaultKeepsMicOn() {
        let selection = RecordingMicSelection.restored(
            enabled: true,
            storedDeviceID: nil,
            availableDeviceIDs: ["built-in"],
            defaultDeviceID: nil
        )
        XCTAssertEqual(selection, RecordingMicSelection(enabled: true, deviceID: nil))
    }

    func testNoMicrophonesTurnsMicOff() {
        let selection = RecordingMicSelection.restored(
            enabled: true,
            storedDeviceID: "usb-mic",
            availableDeviceIDs: [],
            defaultDeviceID: nil
        )
        XCTAssertEqual(selection, RecordingMicSelection(enabled: false, deviceID: nil))
    }
}
