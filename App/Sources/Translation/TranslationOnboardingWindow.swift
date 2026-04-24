// App/Sources/Translation/TranslationOnboardingWindow.swift
import AppKit
import SwiftUI

@MainActor
final class TranslationOnboardingWindow: NSPanel {
    private var onDismissAction: (() -> Void)?

    init(onDismiss: @escaping () -> Void) {
        self.onDismissAction = onDismiss

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = ""
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        self.center()

        let view = TranslationOnboardingView(onDismiss: { [weak self] in
            self?.onDismissAction?()
        })
        self.contentView = NSHostingView(rootView: view)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    override func close() {
        super.close()
    }
}
