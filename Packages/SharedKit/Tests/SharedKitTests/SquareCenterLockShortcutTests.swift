import AppKit
import Carbon.HIToolbox
import Testing
@testable import SharedKit

@Suite("SquareCenterLockShortcut")
struct SquareCenterLockShortcutTests {
    @Test("Default extra key is C")
    func defaultIsC() {
        #expect(SquareCenterLockShortcut.default.keyCode == UInt16(kVK_ANSI_C))
        #expect(SquareCenterLockShortcut.default.displayCharacter == "C")
    }

    @Test("Shift plus the extra key matches")
    func matchesShiftPlusExtraKey() throws {
        let event = try makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_C),
            characters: "c",
            modifierFlags: .shift
        )

        #expect(SquareCenterLockShortcut.default.matches(event))
    }

    @Test("A key repeat does not match")
    func ignoresKeyRepeat() throws {
        let event = try makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_C),
            characters: "c",
            modifierFlags: .shift,
            isARepeat: true
        )

        #expect(!SquareCenterLockShortcut.default.matches(event))
    }

    @Test("Command-Shift-C does not match")
    func ignoresCommandShift() throws {
        let event = try makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_C),
            characters: "c",
            modifierFlags: [.command, .shift]
        )

        #expect(!SquareCenterLockShortcut.default.matches(event))
    }

    @Test("C without Shift does not match")
    func ignoresKeyWithoutShift() throws {
        let event = try makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_C),
            characters: "c",
            modifierFlags: []
        )

        #expect(!SquareCenterLockShortcut.default.matches(event))
    }

    @Test("A different letter does not match the default shortcut")
    func ignoresOtherLetters() throws {
        let event = try makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_X),
            characters: "x",
            modifierFlags: .shift
        )

        #expect(!SquareCenterLockShortcut.default.matches(event))
    }

    @Test("Recording a letter produces an uppercase display character")
    func recordsLetterKey() throws {
        let event = try makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_X),
            characters: "x",
            modifierFlags: .shift
        )
        let shortcut = try #require(SquareCenterLockShortcut(event: event))

        #expect(shortcut.keyCode == UInt16(kVK_ANSI_X))
        #expect(shortcut.displayCharacter == "X")
    }

    @Test("Recording punctuation uses the unshifted glyph")
    func recordsPunctuationKey() throws {
        let event = try makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_Semicolon),
            characters: ";",
            modifierFlags: []
        )
        let shortcut = try #require(SquareCenterLockShortcut(event: event))

        #expect(shortcut.keyCode == UInt16(kVK_ANSI_Semicolon))
        #expect(shortcut.displayCharacter == ";")
    }

    @Test("Recording a symbol key uses the unshifted glyph")
    func recordsMinusKey() throws {
        let event = try makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_Minus),
            characters: "-",
            modifierFlags: []
        )
        let shortcut = try #require(SquareCenterLockShortcut(event: event))

        #expect(shortcut.keyCode == UInt16(kVK_ANSI_Minus))
        #expect(shortcut.displayCharacter == "-")
    }

    @Test("Recording while Shift is held still stores the unshifted punctuation glyph")
    func recordsShiftedPunctuationAsUnshiftedGlyph() throws {
        let event = try makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_Semicolon),
            characters: ":",
            modifierFlags: .shift
        )
        let shortcut = try #require(SquareCenterLockShortcut(event: event))

        #expect(shortcut.keyCode == UInt16(kVK_ANSI_Semicolon))
        #expect(shortcut.displayCharacter == ";")
    }

    @Test("Recording a function key uses its F-number label")
    func recordsFunctionKey() throws {
        let event = try makeKeyEvent(
            keyCode: UInt16(kVK_F5),
            characters: "",
            modifierFlags: []
        )
        let shortcut = try #require(SquareCenterLockShortcut(event: event))

        #expect(shortcut.keyCode == UInt16(kVK_F5))
        #expect(shortcut.displayCharacter == "F5")
    }

    @Test("Shift plus a recorded punctuation key matches")
    func matchesShiftPlusPunctuation() throws {
        let shortcut = SquareCenterLockShortcut(
            keyCode: UInt16(kVK_ANSI_Semicolon),
            displayCharacter: ";"
        )
        let event = try makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_Semicolon),
            characters: ":",
            modifierFlags: .shift
        )

        #expect(shortcut.matches(event))
    }

    @Test("Reserved keys cannot be recorded", arguments: [
        (UInt16(kVK_Escape), "\u{1B}"),
        (UInt16(kVK_Space), " "),
        (UInt16(kVK_Return), "\r"),
        (UInt16(kVK_Tab), "\t"),
        (UInt16(kVK_Delete), "\u{8}"),
        (UInt16(kVK_LeftArrow), ""),
        (UInt16(kVK_Shift), ""),
        (UInt16(kVK_Command), ""),
        (UInt16(kVK_Option), ""),
        (UInt16(kVK_Control), ""),
    ])
    func rejectsReservedKeys(keyCode: UInt16, characters: String) throws {
        let event = try makeKeyEvent(
            keyCode: keyCode,
            characters: characters,
            modifierFlags: []
        )

        #expect(SquareCenterLockShortcut(event: event) == nil)
    }

    @Test("Command-modified keys cannot be recorded")
    func rejectsCommandModifiedKeys() throws {
        let event = try makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_C),
            characters: "c",
            modifierFlags: .command
        )

        #expect(SquareCenterLockShortcut(event: event) == nil)
    }

    @Test("An unrecognized stored shortcut falls back to C")
    func invalidStoredValuesFallBackToDefault() {
        #expect(
            SquareCenterLockShortcut(storedKeyCode: Int(kVK_Escape), storedDisplayCharacter: "C")
                == .default
        )
        #expect(
            SquareCenterLockShortcut(storedKeyCode: Int(kVK_ANSI_X), storedDisplayCharacter: "")
                == .default
        )
        #expect(
            SquareCenterLockShortcut(storedKeyCode: nil, storedDisplayCharacter: nil)
                == .default
        )
    }

    @Test("A valid stored shortcut is restored")
    func validStoredShortcutRestores() {
        let restored = SquareCenterLockShortcut(
            storedKeyCode: Int(kVK_ANSI_X),
            storedDisplayCharacter: "X"
        )

        #expect(restored.keyCode == UInt16(kVK_ANSI_X))
        #expect(restored.displayCharacter == "X")
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        characters: String,
        modifierFlags: NSEvent.ModifierFlags,
        isARepeat: Bool = false
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
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
