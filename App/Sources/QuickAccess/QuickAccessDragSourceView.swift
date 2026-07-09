// App/Sources/QuickAccess/QuickAccessDragSourceView.swift
import AppKit
import SwiftUI

struct QuickAccessDragSourceView: NSViewRepresentable {
    let thumbnail: NSImage
    let dragImageSize: CGSize
    let fileURLProvider: () -> URL?
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void

    init(
        thumbnail: NSImage,
        dragImageSize: CGSize,
        fileURLProvider: @escaping () -> URL?,
        onDragStarted: @escaping () -> Void,
        onDragEnded: @escaping () -> Void
    ) {
        self.thumbnail = thumbnail
        self.dragImageSize = dragImageSize
        self.fileURLProvider = fileURLProvider
        self.onDragStarted = onDragStarted
        self.onDragEnded = onDragEnded
    }

    func makeNSView(context: Context) -> DragSourceNSView {
        DragSourceNSView(
            thumbnail: thumbnail,
            dragImageSize: dragImageSize,
            fileURLProvider: fileURLProvider,
            onDragStarted: onDragStarted,
            onDragEnded: onDragEnded
        )
    }

    func updateNSView(_ nsView: DragSourceNSView, context: Context) {
        nsView.thumbnail = thumbnail
        nsView.dragImageSize = dragImageSize
        nsView.fileURLProvider = fileURLProvider
        nsView.onDragStarted = onDragStarted
        nsView.onDragEnded = onDragEnded
    }
}

final class DragSourceNSView: NSView, NSDraggingSource {
    private static let dragStartThreshold: CGFloat = 4

    var thumbnail: NSImage
    var dragImageSize: CGSize
    var fileURLProvider: () -> URL?
    var onDragStarted: () -> Void
    var onDragEnded: () -> Void

    private var mouseDownEvent: NSEvent?
    private var isDragging = false

    init(
        thumbnail: NSImage,
        dragImageSize: CGSize,
        fileURLProvider: @escaping () -> URL?,
        onDragStarted: @escaping () -> Void,
        onDragEnded: @escaping () -> Void
    ) {
        self.thumbnail = thumbnail
        self.dragImageSize = dragImageSize
        self.fileURLProvider = fileURLProvider
        self.onDragStarted = onDragStarted
        self.onDragEnded = onDragEnded
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownEvent else { return }
        guard dragDistance(from: mouseDownEvent, to: event) >= Self.dragStartThreshold else { return }
        guard let fileURL = fileURLProvider() else { return }

        self.mouseDownEvent = nil
        beginDrag(for: fileURL, from: mouseDownEvent)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        guard isDragging else { return }
        isDragging = false
        onDragEnded()
    }

    private func beginDrag(for fileURL: URL, from event: NSEvent) {
        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        draggingItem.setDraggingFrame(draggingFrame, contents: dragImage)

        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
        isDragging = true
        onDragStarted()
    }

    private var draggingFrame: NSRect {
        let size = NSSize(width: dragImageSize.width, height: dragImageSize.height)
        let origin = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        return NSRect(origin: origin, size: size)
    }

    private var dragImage: NSImage {
        let size = NSSize(width: dragImageSize.width, height: dragImageSize.height)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)
        let clipPath = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        clipPath.addClip()

        NSColor.black.withAlphaComponent(0.12).setFill()
        rect.fill()

        thumbnail.draw(
            in: aspectFitRect(for: thumbnail.size, in: rect),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        NSColor.black.withAlphaComponent(0.18).setStroke()
        clipPath.lineWidth = 1
        clipPath.stroke()
        return image
    }

    private func aspectFitRect(for imageSize: NSSize, in bounds: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func dragDistance(from startEvent: NSEvent, to currentEvent: NSEvent) -> CGFloat {
        let start = startEvent.locationInWindow
        let current = currentEvent.locationInWindow
        let dx = current.x - start.x
        let dy = current.y - start.y
        return sqrt(dx * dx + dy * dy)
    }
}
