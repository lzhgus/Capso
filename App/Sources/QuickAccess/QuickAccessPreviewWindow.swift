import AppKit
import SharedKit

@MainActor
final class QuickAccessPreviewWindow: NSPanel {
    var onClose: (() -> Void)?

    init(image: CGImage, anchorScreen: NSScreen?) {
        let screen = anchorScreen ?? NSScreen.main ?? NSScreen.screens.first!
        let imageSize = CGSize(width: image.width, height: image.height)
        let previewSize = QuickAccessPreviewGeometry.contentSize(
            imagePixelSize: imageSize,
            availableSize: screen.visibleFrame.size,
            maxViewportFraction: 0.82
        )
        let contentWidth = max(320, previewSize.width)
        let contentHeight = max(220, previewSize.height)
        let contentRect = NSRect(
            x: screen.visibleFrame.midX - contentWidth / 2,
            y: screen.visibleFrame.midY - contentHeight / 2,
            width: contentWidth,
            height: contentHeight
        )

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = String(localized: "Preview")
        self.level = .normal
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.isRestorable = false
        self.minSize = NSSize(width: 320, height: 220)
        self.collectionBehavior = [.canJoinAllSpaces]

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: contentRect.size))
        imageView.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.black.cgColor
        self.contentView = imageView
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        onClose?()
        super.close()
    }
}
