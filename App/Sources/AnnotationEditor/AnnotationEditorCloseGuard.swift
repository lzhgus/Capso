// App/Sources/AnnotationEditor/AnnotationEditorCloseGuard.swift
import AppKit

@MainActor
enum AnnotationEditorCloseGuard {
    static func shouldClose(hasUnsavedChanges: Bool, confirmDiscard: () -> Bool) -> Bool {
        !hasUnsavedChanges || confirmDiscard()
    }

    static func presentDiscardAlert(above window: NSWindow?) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Discard your edits?")
        alert.informativeText = String(localized: "Your annotations haven't been saved and will be lost.")
        alert.addButton(withTitle: String(localized: "Discard"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        // The inline area-capture editor's panel sits at `.screenSaver` level;
        // an unparented alert would render behind it, so lift the alert above
        // whichever window is asking.
        if let window {
            alert.window.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        }

        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }
}
