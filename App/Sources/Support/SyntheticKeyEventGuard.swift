// App/Sources/Support/SyntheticKeyEventGuard.swift
import AppKit

/// Guards against synthetic ⌘C / ⇧⌘C posted by word-lookup tools.
///
/// Translation utilities install a global mouse-up sniffer and inject ⌘C to
/// harvest the selection. When a Capso panel is key, the injected chord used
/// to trigger "copy and close" and tear the capture down mid-edit.
extension NSEvent {
    /// True when this ⌘C or ⇧⌘C was posted by another process.
    var isInjectedCopyShortcut: Bool {
        guard type == .keyDown,
              let sourcePID = cgEvent?.getIntegerValueField(.eventSourceUnixProcessID),
              sourcePID != 0,
              sourcePID != Int64(getpid()) else {
            return false
        }
        let mods = modifierFlags.intersection([.command, .shift, .option, .control])
        if mods == [.command, .shift], keyCode == 8 { return true }  // ⇧⌘C
        if mods == .command, charactersIgnoringModifiers?.lowercased() == "c" {
            return true  // ⌘C
        }
        return false
    }
}
