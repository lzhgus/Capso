import AppKit

enum SelectedTextReader {
    @MainActor
    static func readSelectedText() async -> String? {
        if let text = accessibilitySelectedText() {
            return text
        }
        return await copySelectedText()
    }

    @MainActor
    private static func accessibilitySelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success else {
            return nil
        }
        guard let focusedValue else { return nil }
        let focused = focusedValue as! AXUIElement

        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        ) == .success else {
            return nil
        }
        return cleaned(selectedValue as? String)
    }

    @MainActor
    private static func copySelectedText() async -> String? {
        let pasteboard = NSPasteboard.general
        let savedItems = (pasteboard.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }

        pasteboard.clearContents()
        postCopyShortcut()
        try? await Task.sleep(nanoseconds: 120_000_000)
        let copied = cleaned(pasteboard.string(forType: .string))

        pasteboard.clearContents()
        if !savedItems.isEmpty {
            pasteboard.writeObjects(savedItems)
        }
        return copied
    }

    private static func postCopyShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func cleaned(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
