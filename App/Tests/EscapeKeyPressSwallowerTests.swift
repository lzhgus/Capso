import AppKit
import XCTest
@testable import Capso

final class EscapeKeyPressFilterTests: XCTestCase {
    private let escape = EscapeKeyPressFilter.escapeKeyCode

    func testSwallowsNothingUntilArmed() {
        var filter = EscapeKeyPressFilter()
        XCTAssertFalse(filter.shouldSwallow(isKeyDown: true, keyCode: escape, isRepeat: true))
        XCTAssertFalse(filter.shouldSwallow(isKeyDown: false, keyCode: escape, isRepeat: false))
    }

    func testSwallowsRepeatsAndReleaseOfTheHandledPress() {
        var filter = EscapeKeyPressFilter()
        filter.arm()

        XCTAssertTrue(filter.shouldSwallow(isKeyDown: true, keyCode: escape, isRepeat: true))
        XCTAssertTrue(filter.shouldSwallow(isKeyDown: true, keyCode: escape, isRepeat: true))
        XCTAssertTrue(filter.isArmed)

        XCTAssertTrue(filter.shouldSwallow(isKeyDown: false, keyCode: escape, isRepeat: false))
        XCTAssertFalse(filter.isArmed)

        // The next press belongs to whatever is in front now.
        XCTAssertFalse(filter.shouldSwallow(isKeyDown: true, keyCode: escape, isRepeat: false))
    }

    func testFreshEscapePressEndsSwallowingAndIsLetThrough() {
        var filter = EscapeKeyPressFilter()
        filter.arm()

        XCTAssertFalse(filter.shouldSwallow(isKeyDown: true, keyCode: escape, isRepeat: false))
        XCTAssertFalse(filter.isArmed)
    }

    func testOtherKeysAreNeverSwallowed() {
        var filter = EscapeKeyPressFilter()
        filter.arm()

        XCTAssertFalse(filter.shouldSwallow(isKeyDown: true, keyCode: 0, isRepeat: false))
        XCTAssertFalse(filter.shouldSwallow(isKeyDown: true, keyCode: 0, isRepeat: true))
        XCTAssertFalse(filter.shouldSwallow(isKeyDown: false, keyCode: 0, isRepeat: false))
        XCTAssertTrue(filter.isArmed)
    }
}

@MainActor
final class EscapeKeyPressSwallowerTests: XCTestCase {
    func testSwallowsRemainderOfEscapePress() throws {
        let swallower = EscapeKeyPressSwallower(isEscapeKeyDown: { true })
        swallower.swallowRemainder(of: try keyEvent(.keyDown))
        XCTAssertTrue(swallower.isSwallowing)

        XCTAssertNil(swallower.handle(try keyEvent(.keyDown, isARepeat: true)))
        let other = try keyEvent(.keyDown, keyCode: 0, characters: "a")
        XCTAssertTrue(swallower.handle(other) === other)
        XCTAssertNil(swallower.handle(try keyEvent(.keyUp)))
        XCTAssertFalse(swallower.isSwallowing)

        let nextPress = try keyEvent(.keyDown)
        XCTAssertTrue(swallower.handle(nextPress) === nextPress)
    }

    func testIgnoresEventsOtherThanEscapeKeyDown() throws {
        let swallower = EscapeKeyPressSwallower(isEscapeKeyDown: { true })
        swallower.swallowRemainder(of: nil)
        swallower.swallowRemainder(of: try keyEvent(.keyUp))
        swallower.swallowRemainder(of: try keyEvent(.keyDown, keyCode: 0, characters: "a"))
        XCTAssertFalse(swallower.isSwallowing)
    }

    func testStopsWhenEscapeIsReleasedWithoutDeliveringKeyUp() throws {
        var isDown = true
        let swallower = EscapeKeyPressSwallower(isEscapeKeyDown: { isDown })
        swallower.swallowRemainder(of: try keyEvent(.keyDown))
        isDown = false

        let stopped = expectation(description: "stops after release check")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            XCTAssertFalse(swallower.isSwallowing)
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 3)
    }

    private func keyEvent(
        _ type: NSEvent.EventType,
        keyCode: UInt16 = EscapeKeyPressFilter.escapeKeyCode,
        characters: String = "\u{1B}",
        isARepeat: Bool = false
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isARepeat,
            keyCode: keyCode
        ))
    }
}
