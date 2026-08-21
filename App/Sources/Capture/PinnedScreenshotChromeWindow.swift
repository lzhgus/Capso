// App/Sources/Capture/PinnedScreenshotChromeWindow.swift
import AppKit

@MainActor
final class PinnedScreenshotChromeWindow: NSPanel {
    let chromeView: PinnedScreenshotChromeView

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: CGRect, activatesApp: Bool = true) {
        chromeView = PinnedScreenshotChromeView(frame: NSRect(origin: .zero, size: frame.size))

        super.init(
            contentRect: frame,
            styleMask: activatesApp ? [.borderless] : [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces]

        chromeView.autoresizingMask = [.width, .height]
        contentView = chromeView
    }

    func sync(to frame: CGRect) {
        setFrame(frame, display: true)
    }
}
