// App/Sources/OCR/OCROverlayWindow.swift
import AppKit
import SwiftUI
import OCRKit

@MainActor
final class OCROverlayWindow: NSPanel {
    var onClose: (() -> Void)?

    init(image: CGImage, regions: [TextRegion], anchorScreen: NSScreen? = nil) {
        // Pick the screen the capture came from, not the primary by default.
        // `NSWindow.center()` centers within the window's *current* screen,
        // which for a freshly-constructed window is the primary — so relying
        // on it means secondary-display captures always open on main.
        let screen = anchorScreen ?? NSScreen.main ?? NSScreen.screens.first!
        let size = NSSize(width: 900, height: 550)
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )

        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.title = "OCR — Text Recognition"
        self.isMovableByWindowBackground = false
        self.minSize = NSSize(width: 600, height: 400)

        let view = OCROverlayView(
            image: image,
            regions: regions,
            onClose: { [weak self] in
                self?.close()
            }
        )

        self.contentView = NSHostingView(rootView: view)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    override func close() {
        onClose?()
        super.close()
    }
}
