import AppKit
import Carbon.HIToolbox
import CoreGraphics
import CoreServices
import Foundation

/// The extra key that, while Shift is held, grows a 1:1 selection from the
/// original click as the center. Shift itself is not configurable.
public struct SquareCenterLockShortcut: Equatable, Sendable {
    public let keyCode: UInt16
    public let displayCharacter: String

    public static let `default` = SquareCenterLockShortcut(
        keyCode: UInt16(kVK_ANSI_C),
        displayCharacter: "C"
    )

    public init(keyCode: UInt16, displayCharacter: String) {
        self.keyCode = keyCode
        self.displayCharacter = displayCharacter
    }

    /// Restores a shortcut from `UserDefaults`, falling back to ``default``
    /// when the stored key is missing, empty, or reserved.
    public init(storedKeyCode: Int?, storedDisplayCharacter: String?) {
        guard let storedKeyCode,
              let storedDisplayCharacter,
              !storedDisplayCharacter.isEmpty else {
            self = .default
            return
        }

        let keyCode = UInt16(storedKeyCode)
        guard !Self.reservedKeyCodes.contains(keyCode) else {
            self = .default
            return
        }

        self.keyCode = keyCode
        self.displayCharacter = storedDisplayCharacter
    }

    /// Records the extra key from a key-down event. Returns `nil` for reserved
    /// keys, repeats, and chords that include Command, Option, or Control.
    /// Shift may be held so the recorder can capture the key during ⇧+key.
    public init?(event: NSEvent) {
        guard !event.isARepeat else { return nil }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            return nil
        }
        guard !Self.reservedKeyCodes.contains(event.keyCode) else { return nil }
        guard let display = Self.displayName(for: event) else { return nil }

        self.keyCode = event.keyCode
        self.displayCharacter = display
    }

    /// `true` when `event` is this extra key held with Shift and no other
    /// modifiers — the chord that activates center lock.
    public func matches(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }
        guard event.keyCode == keyCode else { return false }
        return event.modifierFlags.intersection([.command, .shift, .option, .control]) == .shift
    }

    /// `true` when this extra key is currently down, independent of modifiers.
    /// Used to seed center lock on mouse-down if key-down was missed.
    public var isHardwareKeyPressed: Bool {
        CGEventSource.keyState(.hidSystemState, key: keyCode)
    }

    /// Shift plus this extra key is reserved for center lock, so it must not
    /// also switch annotation tools.
    public func blocksToolShortcut(keyCode: UInt16, shiftHeld: Bool) -> Bool {
        shiftHeld && keyCode == self.keyCode
    }

    private static let reservedKeyCodes: Set<UInt16> = [
        UInt16(kVK_Escape),
        UInt16(kVK_Space),
        UInt16(kVK_Return),
        UInt16(kVK_ANSI_KeypadEnter),
        UInt16(kVK_Tab),
        UInt16(kVK_Delete),
        UInt16(kVK_ForwardDelete),
        UInt16(kVK_LeftArrow),
        UInt16(kVK_RightArrow),
        UInt16(kVK_DownArrow),
        UInt16(kVK_UpArrow),
        UInt16(kVK_Shift),
        UInt16(kVK_RightShift),
        UInt16(kVK_Control),
        UInt16(kVK_RightControl),
        UInt16(kVK_Option),
        UInt16(kVK_RightOption),
        UInt16(kVK_Command),
        UInt16(kVK_RightCommand),
        UInt16(kVK_Function),
        UInt16(kVK_CapsLock),
    ]

    /// Labels for keys that do not produce a printable character.
    private static let specialDisplayNames: [UInt16: String] = [
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16", UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20",
        UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟",
    ]

    private static func displayName(for event: NSEvent) -> String? {
        if let special = specialDisplayNames[event.keyCode] {
            return special
        }

        let raw = unshiftedCharacter(for: event.keyCode)
            ?? event.charactersIgnoringModifiers
            ?? ""
        guard raw.count == 1, let character = raw.first else { return nil }
        guard character.isLetter
                || character.isNumber
                || character.isPunctuation
                || character.isSymbol else {
            return nil
        }
        if character.isLetter {
            return String(character).uppercased()
        }
        return String(character)
    }

    private static let layoutLock = NSLock()

    /// Layout-aware glyph for `keyCode` with no modifiers, so Shift+; records as
    /// ";" rather than ":".
    private static func unshiftedCharacter(for keyCode: UInt16) -> String? {
        layoutLock.lock()
        defer { layoutLock.unlock() }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let cfDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(cfDataPtr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let base = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return nil
            }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var actualLength = 0
            let status = chars.withUnsafeMutableBufferPointer { buffer -> OSStatus in
                var length = 0
                let result = UCKeyTranslate(
                    base,
                    keyCode,
                    UInt16(kUCKeyActionDisplay),
                    0,
                    UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    buffer.count,
                    &length,
                    buffer.baseAddress
                )
                actualLength = length
                return result
            }
            guard status == noErr, actualLength > 0 else { return nil }
            let translated = String(utf16CodeUnits: chars, count: actualLength)
            return translated.isEmpty ? nil : translated
        }
    }
}
