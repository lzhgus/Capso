// App/Sources/Support/SyntheticKeyEventGuard.swift
import AppKit

/// Guards the capture and annotation UI against synthetic key events posted
/// by other processes.
///
/// Word-lookup / translation utilities install a global mouse-up sniffer and
/// inject ⌘C via `CGEvent.post` to harvest the current selection. When a
/// Capso panel happens to be key at that moment, the injected chord used to
/// trigger "copy image and close" (and Esc-to-cancel) and tore the capture
/// down while the user was still working.
///
/// Hardware key events report a source PID of 0; events synthesized inside
/// this process (the test suite's `NSEvent.keyEvent(with:)` helpers included)
/// report Capso's own PID; events posted by other processes report the
/// poster's PID — which is what lets the UI tell them apart.
extension NSEvent {
    /// True when this key-down was posted by another process instead of
    /// coming from the hardware or from Capso itself.
    var isPostedByAnotherProcess: Bool {
        guard type == .keyDown,
              let sourcePID = cgEvent?.getIntegerValueField(.eventSourceUnixProcessID),
              sourcePID != 0 else {
            return false
        }
        return sourcePID != Int64(getpid())
    }

    /// True for the chords that commit, dismiss or hand off a capture:
    /// Esc, ⏎ (or keypad Enter), ⇧⌘C, ⌘C, ⌘S, ⌘P — matched exactly the way
    /// the in-app handlers match them. Injected presses of anything else
    /// (⌘V, ⌘Z, plain typing, …) keep their normal behaviour.
    var isCaptureCommitOrDismissShortcut: Bool {
        let mods = modifierFlags.intersection([.command, .shift, .option, .control])
        if keyCode == 53 { return true }                                  // Esc
        if mods.isEmpty, keyCode == 36 || keyCode == 76 { return true }   // ⏎ / keypad Enter
        if mods == [.command, .shift], keyCode == 8 { return true }       // ⇧⌘C
        guard mods == .command else { return false }
        switch charactersIgnoringModifiers?.lowercased() {
        case "c", "s", "p": return true                                   // ⌘C / ⌘S / ⌘P
        default: return false
        }
    }

    /// An injected press of one of the commit/dismiss chords — ignore it.
    var isInjectedCommitOrDismissShortcut: Bool {
        isPostedByAnotherProcess && isCaptureCommitOrDismissShortcut
    }
}
