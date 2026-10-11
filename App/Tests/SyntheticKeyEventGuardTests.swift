import AppKit
import XCTest
@testable import Capso

/// Coverage for the synthetic ⌘C / ⇧⌘C guard that protects capture and
/// annotation UI from translation-tool injections.
@MainActor
final class SyntheticKeyEventGuardTests: XCTestCase {

    func testHardwareKeyEventIsNotInjected() throws {
        let event = try makeKeyEvent(keyCode: 8, command: true, sourcePID: 0)
        XCTAssertFalse(event.isInjectedCopyShortcut)
    }

    func testInProcessSynthesisIsNotInjected() throws {
        let event = try makeKeyEvent(keyCode: 8, command: true, sourcePID: Int64(getpid()))
        XCTAssertFalse(event.isInjectedCopyShortcut)
    }

    func testCommandCFromAnotherProcessIsInjected() throws {
        let event = try makeKeyEvent(keyCode: 8, command: true, sourcePID: 1315)
        XCTAssertTrue(event.isInjectedCopyShortcut)
    }

    func testShiftCommandCFromAnotherProcessIsInjected() throws {
        let event = try makeKeyEvent(keyCode: 8, command: true, shift: true, sourcePID: 9999)
        XCTAssertTrue(event.isInjectedCopyShortcut)
    }

    func testCommandVFromAnotherProcessIsNotInjected() throws {
        let event = try makeKeyEvent(keyCode: 9, command: true, sourcePID: 1234, char: "v")
        XCTAssertFalse(event.isInjectedCopyShortcut)
    }

    func testEscapeFromAnotherProcessIsNotInjected() throws {
        let event = try makeKeyEvent(keyCode: 53, command: false, sourcePID: 5678)
        XCTAssertFalse(event.isInjectedCopyShortcut)
    }

    func testReturnFromAnotherProcessIsNotInjected() throws {
        let event = try makeKeyEvent(keyCode: 36, command: false, sourcePID: 1111)
        XCTAssertFalse(event.isInjectedCopyShortcut)
    }

    func testCommandSFromAnotherProcessIsNotInjected() throws {
        let event = try makeKeyEvent(keyCode: 1, command: true, sourcePID: 2222, char: "s")
        XCTAssertFalse(event.isInjectedCopyShortcut)
    }

    // MARK: - Helpers

    private func makeKeyEvent(
        keyCode: UInt16,
        command: Bool = false,
        shift: Bool = false,
        sourcePID: Int64,
        char: String = "c"
    ) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keyCode),
            keyDown: true
        ))
        cgEvent.setIntegerValueField(.eventSourceUnixProcessID, value: sourcePID)

        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if shift { flags.insert(.maskShift) }
        cgEvent.flags = flags

        if let unichar = char.utf16.first {
            cgEvent.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))
            cgEvent.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            cgEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: [unichar])
        }

        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }
}
