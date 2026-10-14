// App/Sources/CapsoApp.swift
import SwiftUI

@main
enum CapsoMain {
    @MainActor
    static func main() {
        // Finish helper requests before SwiftUI/AppKit starts an application
        // lifecycle. An OCR retry must not take focus from the running app.
        if OCRProcessFallback.runHelperIfRequested() {
            return
        }
        CapsoApp.main()
    }
}

struct CapsoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
