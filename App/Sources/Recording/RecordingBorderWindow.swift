// App/Sources/Recording/RecordingBorderWindow.swift
import AppKit

@MainActor
final class RecordingBorderWindow: NSPanel {
    static let borderWidth: CGFloat = 3
    // Gap between the stroke's inner edge and the capture rect so anti-aliasing
    // can't bleed red into the recorded video.
    static let safetyMargin: CGFloat = 2
    static var outset: CGFloat { borderWidth + safetyMargin }

    // `frame` is the capture rect. The window is expanded outward by
    // `outset` on each side; the stroke is drawn in the outer `borderWidth`
    // of the window, so the red pixels sit entirely outside the capture rect.
    init(frame: CGRect, screen: NSScreen) {
        let outsetFrame = frame.insetBy(dx: -Self.outset, dy: -Self.outset)
        super.init(
            contentRect: outsetFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Avoid the default panel fade-in so the first captured frame never
        // sees a half-rendered border.
        self.animationBehavior = .none

        let borderView = RecordingBorderView(frame: NSRect(origin: .zero, size: outsetFrame.size))
        self.contentView = borderView
    }

    func show() {
        orderFrontRegardless()
    }
    func hide() { orderOut(nil) }
}

private class RecordingBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let borderWidth = RecordingBorderWindow.borderWidth
        // Place the stroke's outer edge on the window's outer edge so the full
        // stroke sits outside the capture rect (which starts `outset` points in).
        let inset = borderWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        context.setShouldAntialias(false)
        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.setLineWidth(borderWidth)
        context.stroke(rect)
    }
}
