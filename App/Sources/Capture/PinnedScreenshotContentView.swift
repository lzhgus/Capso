import AppKit

@MainActor
final class PinnedScreenshotContentView: NSView {
    let imageView: NSImageView
    private let resizeHandle = NSView()

    var isResizable = true {
        didSet {
            resizeHandle.isHidden = !isResizable
        }
    }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Receive clicks ourselves so the first click on an inactive pin can drag it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    init(image: CGImage, frame: NSRect) {
        imageView = NSImageView(frame: frame)
        super.init(frame: frame)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        imageView.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)

        resizeHandle.wantsLayer = true
        resizeHandle.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.65).cgColor
        resizeHandle.layer?.cornerRadius = 2
        resizeHandle.frame = NSRect(x: bounds.width - 14, y: bounds.height - 14, width: 8, height: 8)
        resizeHandle.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(resizeHandle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func isPointInResizeHandle(_ point: NSPoint) -> Bool {
        guard isResizable else { return false }
        return resizeHandle.frame.insetBy(dx: -10, dy: -10).contains(point)
    }
}
