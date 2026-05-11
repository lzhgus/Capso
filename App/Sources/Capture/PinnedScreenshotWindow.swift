// App/Sources/Capture/PinnedScreenshotWindow.swift
import AppKit
import CaptureKit

@MainActor
final class PinnedScreenshotWindow: NSPanel {
    let windowID = UUID()
    private let image: CGImage
    private let onCopy: () -> Void
    private let onSave: () -> Void
    var onDidClose: (UUID) -> Void
    private var screenshotView: PinnedScreenshotContentView!

    private var currentScale: CGFloat = 1.0
    var onFrameChanged: ((CGRect) -> Void)?
    var onScaleChanged: ((Int) -> Void)?
    private var dragStartWindowOrigin: NSPoint?
    private var dragStartMouse: NSPoint?
    private var resizeStartFrame: NSRect?
    private var resizeStartMouse: NSPoint?
    private var isResizing = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(
        image: CGImage,
        anchorRect: CGRect?,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onDidClose: @escaping (UUID) -> Void
    ) {
        self.image = image
        self.onCopy = onCopy
        self.onSave = onSave
        self.onDidClose = onDidClose

        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let maxLongSide: CGFloat = 800
        let scale = min(1.0, maxLongSide / max(imageWidth, imageHeight))
        let width = max(100, imageWidth * scale)
        let height = max(100, imageHeight * scale)

        let screen = anchorRect
            .flatMap { anchor in NSScreen.screens.first(where: { $0.visibleFrame.intersects(anchor) }) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        let x = min(max(visible.midX - width / 2, visible.minX + 16), visible.maxX - width - 16)
        let y = min(max(visible.midY - height / 2, visible.minY + 16), visible.maxY - height - 16)

        super.init(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces]
        contentAspectRatio = NSSize(width: image.width, height: image.height)

        let minScale = max(100 / imageWidth, 100 / imageHeight)
        minSize = NSSize(width: imageWidth * minScale, height: imageHeight * minScale)

        screenshotView = PinnedScreenshotContentView(
            image: image,
            frame: NSRect(origin: .zero, size: NSSize(width: width, height: height))
        )
        screenshotView.autoresizingMask = [.width, .height]
        contentView = screenshotView
        contentView?.menu = makeContextMenu()
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
        } else if event.keyCode == 13 && event.modifierFlags.contains(.command) {
            close()
        } else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "=" {
            adjustScale(by: 1.1)
        } else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "-" {
            adjustScale(by: 1 / 1.1)
        } else {
            super.keyDown(with: event)
        }
    }

    override func close() {
        super.close()
        onDidClose(windowID)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyImage), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let saveItem = NSMenuItem(title: "Save", action: #selector(saveImage), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)

        let closeItem = NSMenuItem(title: "Close", action: #selector(closeWindow), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)

        menu.addItem(.separator())

        let opacityMenu = NSMenu()
        [1.0, 0.75, 0.5, 0.25].forEach { value in
            let title = "\(Int(value * 100))%"
            let item = NSMenuItem(title: title, action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.representedObject = value
            item.target = self
            opacityMenu.addItem(item)
        }

        let opacityItem = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        menu.addItem(opacityItem)
        menu.setSubmenu(opacityMenu, for: opacityItem)
        return menu
    }

    @objc private func copyImage() { onCopy() }
    @objc private func saveImage() { onSave() }
    @objc private func closeWindow() { close() }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        alphaValue = value
    }

    private var baseDisplayWidth: CGFloat {
        max(100, CGFloat(image.width) * min(1.0, 400 / max(CGFloat(image.width), CGFloat(image.height))))
    }

    private func adjustScale(by factor: CGFloat, animate: Bool = true) {
        let oldFrame = frame
        let newWidth = min(max(160, oldFrame.width * factor), 1400)
        let aspect = CGFloat(image.height) / CGFloat(image.width)
        let newHeight = newWidth * aspect

        let newOrigin = NSPoint(
            x: oldFrame.midX - newWidth / 2,
            y: oldFrame.midY - newHeight / 2
        )

        setFrame(NSRect(origin: newOrigin, size: NSSize(width: newWidth, height: newHeight)), display: true, animate: animate)
        currentScale = newWidth / baseDisplayWidth
        onFrameChanged?(frame)
        onScaleChanged?(Int(currentScale * 100))
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase == [] else { return }
        guard let factor = ScrollZoomBehavior.scaleFactor(
            verticalDelta: event.scrollingDeltaY,
            horizontalDelta: event.scrollingDeltaX,
            hasPreciseDeltas: event.hasPreciseScrollingDeltas
        ) else {
            super.scrollWheel(with: event)
            return
        }

        adjustScale(by: factor, animate: false)
    }

    override func mouseDown(with event: NSEvent) {
        let localInWindow = event.locationInWindow
        let localInScreenshot = screenshotView.convert(localInWindow, from: nil)

        if screenshotView.isPointInResizeHandle(localInScreenshot) {
            isResizing = true
            resizeStartFrame = frame
            resizeStartMouse = NSEvent.mouseLocation
            return
        }

        dragStartWindowOrigin = frame.origin
        dragStartMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        if isResizing,
           let startFrame = resizeStartFrame,
           let startMouse = resizeStartMouse {
            let currentMouse = NSEvent.mouseLocation
            let dx = currentMouse.x - startMouse.x
            let dy = startMouse.y - currentMouse.y
            let delta = max(dx, dy)

            let aspect = CGFloat(image.height) / CGFloat(image.width)
            let newWidth = min(max(160, startFrame.width + delta), 1400)
            let newHeight = newWidth * aspect
            let newFrame = NSRect(
                x: startFrame.minX,
                y: startFrame.maxY - newHeight,
                width: newWidth,
                height: newHeight
            )
            setFrame(newFrame, display: true)
            currentScale = newWidth / baseDisplayWidth
            onFrameChanged?(frame)
            onScaleChanged?(Int(currentScale * 100))
            return
        }

        if let startOrigin = dragStartWindowOrigin,
           let startMouse = dragStartMouse {
            let currentMouse = NSEvent.mouseLocation
            let dx = currentMouse.x - startMouse.x
            let dy = currentMouse.y - startMouse.y
            setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
            onFrameChanged?(frame)
        }
    }

    override func mouseUp(with event: NSEvent) {
        isResizing = false
        resizeStartFrame = nil
        resizeStartMouse = nil
        dragStartWindowOrigin = nil
        dragStartMouse = nil
        super.mouseUp(with: event)
    }
}
