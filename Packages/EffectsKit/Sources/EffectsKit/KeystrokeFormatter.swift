import AppKit
import Carbon.HIToolbox
import CoreServices

// Keystroke label mapping is adapted from KeyCastr
// (https://github.com/keycastr/keycastr), which is licensed under the
// BSD 3-Clause License. Portions of the special-key table and transform
// rules follow `KCEventTransformer` / `KCKeystroke`.
//
// Copyright (c) 2009 Stephen Deken.
// Copyright (c) 2017-2024 Andrew Kitchen.
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
//  * Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//  * Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//  * Neither the name KeyCastr nor the names of its contributors may be used
//    to endorse or promote products derived from this software without specific
//    prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Full third-party notices: see THIRD_PARTY_NOTICES.md at the repository root.

/// Maps key-down events into KeyCastr-style display labels.
///
/// Aligned with KeyCastr `KCEventTransformer` / `KCKeystroke`:
/// - Modifier order: ⌃ ⌥ ⇧ ⌘
/// - “Command-ish” = ⌘ or ⌃ (uppercase + break bezel line upstream)
/// - Body via `UCKeyTranslate` for the current keyboard layout
/// - Special keys use KeyCastr’s keyCode → glyph table
public enum KeystrokeFormatter {
    public struct Keystroke: Sendable, Equatable {
        public let keyCode: UInt16
        public let characters: String
        public let charactersIgnoringModifiers: String
        public let modifierFlags: NSEvent.ModifierFlags

        public init(
            keyCode: UInt16,
            characters: String,
            charactersIgnoringModifiers: String,
            modifierFlags: NSEvent.ModifierFlags
        ) {
            self.keyCode = keyCode
            self.characters = characters
            self.charactersIgnoringModifiers = charactersIgnoringModifiers
            self.modifierFlags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        }

        public init(event: NSEvent) {
            self.init(
                keyCode: event.keyCode,
                characters: event.characters ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                modifierFlags: event.modifierFlags
            )
        }

        /// KeyCastr: Control OR Command.
        public var isCommand: Bool {
            modifierFlags.contains(.control) || modifierFlags.contains(.command)
        }

        public var isModified: Bool {
            !modifierFlags.intersection([.control, .command, .option, .shift]).isEmpty
        }
    }

    public static func displayString(for event: NSEvent) -> String? {
        guard event.type == .keyDown, !event.isARepeat else { return nil }
        return displayString(for: Keystroke(event: event))
    }

    public static func displayString(for keystroke: Keystroke) -> String? {
        if isModifierKeyCode(Int(keystroke.keyCode)) { return nil }
        return transform(keystroke)
    }

    // MARK: - Transform (KeyCastr KCEventTransformer)

    private static func transform(_ keystroke: Keystroke) -> String {
        let flags = keystroke.modifierFlags
        let hasOption = flags.contains(.option)
        let hasShift = flags.contains(.shift)
        let isCommand = keystroke.isCommand

        // KeyCastr modifier order: Control, Option, Shift, Command.
        var response = ""
        if flags.contains(.control) { response += "⌃" }
        if hasOption { response += "⌥" }
        if hasShift { response += "⇧" }
        if flags.contains(.command) { response += "⌘" }

        // Bare shift-tab → left tab (KeyCastr special case).
        if hasShift, !isCommand, !hasOption, Int(keystroke.keyCode) == kVK_Tab {
            return "⇧⇤"
        }

        if let special = specialKeys[Int(keystroke.keyCode)] {
            return response + special
        }

        var body = translateKeyCode(keystroke.keyCode)
        if body.isEmpty {
            body = keystroke.charactersIgnoringModifiers
        }
        if body.isEmpty {
            body = keystroke.characters
        }
        if body.isEmpty {
            body = "?"
        }
        response += body

        // Commands / shifted keystrokes uppercased (KeyCastr skips keyCode 27).
        if (isCommand || hasShift), keystroke.keyCode != 27 {
            response = response.uppercased()
        }
        return response
    }

    private static func translateKeyCode(_ keyCode: UInt16) -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return ""
        }
        guard let cfDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return ""
        }
        let data = Unmanaged<CFData>.fromOpaque(cfDataPtr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String in
            guard let base = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return "" }
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
            guard status == noErr, actualLength > 0 else { return "" }
            return String(utf16CodeUnits: chars, count: actualLength)
        }
    }

    private static func isModifierKeyCode(_ keyCode: Int) -> Bool {
        switch keyCode {
        case kVK_Shift, kVK_RightShift,
             kVK_Command, kVK_RightCommand,
             kVK_Option, kVK_RightOption,
             kVK_Control, kVK_RightControl,
             kVK_Function, kVK_CapsLock:
            return true
        default:
            return false
        }
    }

    /// KeyCastr `_specialKeys` table.
    /// Space uses U+2423 OPEN BOX (␣), matching KeyCastr — never the word "Space",
    /// which glued into typing as `SpaceSpacezxcss`.
    private static let specialKeys: [Int: String] = [
        126: "↑", 125: "↓", 124: "→", 123: "←",
        48: "⇥", 53: "⎋", 71: "⌧", 51: "⌫", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        36: "↩", 76: "↩",
        49: "␣", // open box (KeyCastr space glyph)
        122: "F1", 120: "F2", 99: "F3", 118: "F4",
        96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16",
        64: "F17", 79: "F18", 80: "F19", 90: "F20",
        0x66: "英数", 0x68: "かな",
    ]
}
