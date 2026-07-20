import AppKit
import Carbon.HIToolbox
import Testing
@testable import EffectsKit

@Suite("KeystrokeFormatter")
struct KeystrokeFormatterTests {
    @Test("Ignores non key-down events")
    func ignoresNonKeyDown() {
        let event = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(kVK_Command)
        )
        #expect(event.flatMap { KeystrokeFormatter.displayString(for: $0) } == nil)
    }

    @Test("Formats command-letter shortcuts")
    func formatsCommandLetterShortcuts() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_C)
        ))
        let label = try #require(KeystrokeFormatter.displayString(for: event))
        #expect(label.contains("⌘"))
        #expect(label.uppercased().contains("C"))
    }

    @Test("Formats special keys")
    func formatsSpecialKeys() throws {
        let space = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: UInt16(kVK_Space)
        ))
        // KeyCastr uses U+2423 OPEN BOX, not the word "Space".
        #expect(KeystrokeFormatter.displayString(for: space) == "␣")

        let esc = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: UInt16(kVK_Escape)
        ))
        #expect(KeystrokeFormatter.displayString(for: esc) == "⎋")
    }

    @Test("Skips key repeats and pure modifier keys")
    func skipsRepeatsAndModifiers() throws {
        let repeatEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: true,
            keyCode: UInt16(kVK_ANSI_A)
        ))
        #expect(KeystrokeFormatter.displayString(for: repeatEvent) == nil)

        let shiftOnly = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(kVK_Shift)
        ))
        #expect(KeystrokeFormatter.displayString(for: shiftOnly) == nil)
    }

    @Test("Keystroke isCommand matches KeyCastr Control-or-Command rule")
    func isCommandRule() {
        let cmd = KeystrokeFormatter.Keystroke(
            keyCode: UInt16(kVK_ANSI_C),
            characters: "c",
            charactersIgnoringModifiers: "c",
            modifierFlags: [.command]
        )
        #expect(cmd.isCommand)

        let ctrl = KeystrokeFormatter.Keystroke(
            keyCode: UInt16(kVK_ANSI_C),
            characters: "c",
            charactersIgnoringModifiers: "c",
            modifierFlags: [.control]
        )
        #expect(ctrl.isCommand)

        let plain = KeystrokeFormatter.Keystroke(
            keyCode: UInt16(kVK_ANSI_C),
            characters: "c",
            charactersIgnoringModifiers: "c",
            modifierFlags: []
        )
        #expect(!plain.isCommand)
    }
}
