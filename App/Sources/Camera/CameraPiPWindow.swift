// App/Sources/Camera/CameraPiPWindow.swift
import AppKit
import SwiftUI
import CameraKit
import SharedKit

@MainActor
final class CameraPiPWindow: NSPanel {
    private let cameraManager: CameraManager
    private let settings: AppSettings
    private var menuBuilder: CameraMenuBuilder?

    private var resizeStartFrame: NSRect?
    private var resizeStartMouse: NSPoint?
    private var isResizing = false
    private let recordingFrame: CGRect?
    private var isPresentationMode = false
    private var isPresentationTransitioning = false
    private var allowsPresentationFrameOutsideVisibleArea = false
    private var storedPiPFrame: CGRect?
    private var mouseDownPoint: NSPoint?
    private let clickThreshold: CGFloat = 5
    private let defaultWindowLevel: NSWindow.Level = .floating
    private let presentationWindowLevel = NSWindow.Level.statusBar + 1
    private let defaultCollectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .transient]
    private let presentationCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .transient
    ]

    var presentationModeActive: Bool {
        isPresentationMode
    }

    var restartRestorationState: CameraPiPRestorationState {
        CameraPiPPlacement.restorationState(
            currentFrame: frame,
            storedPiPFrame: storedPiPFrame,
            presentationModeActive: isPresentationMode
        )
    }

    init(
        cameraManager: CameraManager,
        settings: AppSettings,
        recordingFrame: CGRect? = nil,
        restorationState: CameraPiPRestorationState? = nil
    ) {
        self.cameraManager = cameraManager
        self.settings = settings
        self.recordingFrame = recordingFrame

        let initialSize = Self.windowSize(shape: settings.cameraShape, settings: settings)

        let screen = Self.placementScreen(for: restorationState?.restoredFrame ?? recordingFrame)
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        let initialFrame = CameraPiPPlacement.initialFrame(
            restorationState: restorationState,
            defaultSize: initialSize,
            recordingFrame: recordingFrame,
            visibleFrame: screen.visibleFrame
        )
        let shouldRestorePresentation = restorationState?.presentationModeActive == true && recordingFrame != nil

        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = defaultWindowLevel
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = defaultCollectionBehavior
        self.isMovableByWindowBackground = true
        if shouldRestorePresentation {
            self.isPresentationMode = true
            self.storedPiPFrame = CameraPiPPlacement.frame(
                restoredFrame: restorationState?.restoredFrame,
                defaultSize: initialSize,
                recordingFrame: recordingFrame,
                visibleFrame: screen.visibleFrame
            )
            applyPresentationWindowMode()
        }

        installContentView()

        // Snap to corners when dragged near screen edges
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowMoved),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    func show() { makeKeyAndOrderFront(nil) }

    func togglePresentationMode() {
        guard !isPresentationTransitioning else { return }

        if isPresentationMode {
            exitPresentationMode()
            return
        }

        guard let targetFrame = presentationFrame() else { return }

        storedPiPFrame = frame
        isPresentationMode = true
        isPresentationTransitioning = true
        applyPresentationWindowMode()

        // Animate to fill the recording area.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(targetFrame, display: true)
        } completionHandler: {
            self.installContentView()
            self.isPresentationTransitioning = false
        }
    }

    func exitPresentationMode() {
        guard !isPresentationTransitioning else { return }
        guard isPresentationMode else { return }
        guard let storedPiPFrame else {
            isPresentationMode = false
            installContentView()
            restoreDefaultWindowMode()
            return
        }

        isPresentationMode = false
        isPresentationTransitioning = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(storedPiPFrame, display: true)
        } completionHandler: {
            self.installContentView()
            self.storedPiPFrame = nil
            self.isPresentationTransitioning = false
            self.restoreDefaultWindowMode()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(at: event.locationInWindow)
    }

    private func showContextMenu(at point: NSPoint) {
        let builder = CameraMenuBuilder(settings: settings)
        builder.selectedCameraID = cameraManager.selectedDeviceID
        builder.onShapeSelected = { [weak self] _ in self?.applySettings() }
        builder.onSizeSelected = { [weak self] _ in self?.applySettings() }
        builder.onMirrorToggled = { [weak self] _ in self?.applySettings() }
        // PiP context menu doesn't change camera device — toolbar handles enable/disable.
        builder.onCameraSelected = nil
        builder.onMenuClosed = { [weak self] in self?.menuBuilder = nil }
        self.menuBuilder = builder

        let menu = builder.buildMenu()
        menu.popUp(positioning: nil, at: point, in: self.contentView)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = NSEvent.mouseLocation
        let local = event.locationInWindow
        // Check if click is in the bottom-right 20x20 corner (resize handle zone)
        let handleZone = NSRect(
            x: self.frame.width - 20,
            y: 0,
            width: 20,
            height: 20
        )
        if !isPresentationMode && handleZone.contains(local) {
            isResizing = true
            resizeStartFrame = self.frame
            resizeStartMouse = NSEvent.mouseLocation
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isResizing,
              let startFrame = resizeStartFrame,
              let startMouse = resizeStartMouse else {
            super.mouseDragged(with: event)
            return
        }

        let currentMouse = NSEvent.mouseLocation
        // Drag right to grow width, drag down to grow height (window y is bottom-up)
        let dx = currentMouse.x - startMouse.x
        let dy = startMouse.y - currentMouse.y

        // Use the larger of dx or dy to determine new shorter dimension
        let aspect = settings.cameraShape.aspectRatio
        let oldShorter: CGFloat
        if aspect >= 1 {
            oldShorter = startFrame.height
        } else {
            oldShorter = startFrame.width
        }

        let delta = max(dx, dy)
        let newShorter = max(80, min(400, oldShorter + delta))

        settings.cameraCustomSizePt = Double(newShorter)
        applySettings()
    }

    override func mouseUp(with event: NSEvent) {
        if isResizing {
            isResizing = false
            resizeStartFrame = nil
            resizeStartMouse = nil
            mouseDownPoint = nil
            return
        }

        defer { mouseDownPoint = nil }

        guard let mouseDownPoint else {
            super.mouseUp(with: event)
            return
        }

        let mouseUpPoint = NSEvent.mouseLocation
        let dx = mouseUpPoint.x - mouseDownPoint.x
        let dy = mouseUpPoint.y - mouseDownPoint.y
        let movedDistance = sqrt(dx * dx + dy * dy)

        // A small-movement click toggles presentation mode.
        if movedDistance <= clickThreshold {
            togglePresentationMode()
            return
        }

        super.mouseUp(with: event)
    }

    @objc private func handleWindowMoved() {
        guard !isPresentationMode && !isPresentationTransitioning else { return }

        // Skip snap if Cmd is held
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) { return }

        guard let screen = self.screen else { return }
        let screenFrame = screen.visibleFrame
        let windowFrame = self.frame
        let snapRadius: CGFloat = 60
        let margin: CGFloat = 16

        // Compute distances from each screen corner
        let topLeft = NSPoint(x: screenFrame.minX, y: screenFrame.maxY)
        let topRight = NSPoint(x: screenFrame.maxX, y: screenFrame.maxY)
        let bottomLeft = NSPoint(x: screenFrame.minX, y: screenFrame.minY)
        let bottomRight = NSPoint(x: screenFrame.maxX, y: screenFrame.minY)

        // The window's matching corner for each screen corner
        let windowTopLeft = NSPoint(x: windowFrame.minX, y: windowFrame.maxY)
        let windowTopRight = NSPoint(x: windowFrame.maxX, y: windowFrame.maxY)
        let windowBottomLeft = NSPoint(x: windowFrame.minX, y: windowFrame.minY)
        let windowBottomRight = NSPoint(x: windowFrame.maxX, y: windowFrame.minY)

        let dTL = distance(windowTopLeft, topLeft)
        let dTR = distance(windowTopRight, topRight)
        let dBL = distance(windowBottomLeft, bottomLeft)
        let dBR = distance(windowBottomRight, bottomRight)

        let minDist = min(dTL, dTR, dBL, dBR)
        guard minDist <= snapRadius else { return }

        var newOrigin = windowFrame.origin
        if minDist == dTL {
            newOrigin = NSPoint(x: screenFrame.minX + margin, y: screenFrame.maxY - windowFrame.height - margin)
        } else if minDist == dTR {
            newOrigin = NSPoint(x: screenFrame.maxX - windowFrame.width - margin, y: screenFrame.maxY - windowFrame.height - margin)
        } else if minDist == dBL {
            newOrigin = NSPoint(x: screenFrame.minX + margin, y: screenFrame.minY + margin)
        } else if minDist == dBR {
            newOrigin = NSPoint(x: screenFrame.maxX - windowFrame.width - margin, y: screenFrame.minY + margin)
        }

        if newOrigin != windowFrame.origin {
            self.setFrameOrigin(newOrigin)
        }
    }

    private func distance(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var canBecomeKey: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        if allowsPresentationFrameOutsideVisibleArea {
            return frameRect
        }

        return super.constrainFrameRect(frameRect, to: screen)
    }

    /// Re-read settings and update the window's size + content view.
    func applySettings() {
        let newSize = Self.windowSize(shape: settings.cameraShape, settings: settings)
        var newFrame = self.frame
        // Keep top-left fixed when resizing
        newFrame.origin.y += newFrame.size.height - newSize.height
        newFrame.size = newSize
        self.setFrame(newFrame, display: true, animate: true)
        installContentView()
    }

    /// Compute the window content size for the given shape, honoring custom size override.
    static func windowSize(shape: CameraShape, settings: AppSettings) -> CGSize {
        let shorter: CGFloat
        if settings.cameraCustomSizePt > 0 {
            shorter = CGFloat(settings.cameraCustomSizePt)
        } else {
            shorter = settings.cameraSize.shorterDimension
        }
        if shape.aspectRatio >= 1 {
            return CGSize(width: shorter * shape.aspectRatio, height: shorter)
        } else {
            return CGSize(width: shorter, height: shorter / shape.aspectRatio)
        }
    }

    private static func placementScreen(for restoredFrame: CGRect?) -> NSScreen? {
        guard let restoredFrame else { return nil }
        return NSScreen.screens
            .compactMap { screen -> (screen: NSScreen, area: CGFloat)? in
                let intersection = restoredFrame.intersection(screen.visibleFrame)
                guard !intersection.isNull, !intersection.isEmpty else { return nil }
                return (screen, intersection.width * intersection.height)
            }
            .max { $0.area < $1.area }?
            .screen
    }

    private func presentationFrame() -> CGRect? {
        recordingFrame
    }

    private func applyPresentationWindowMode() {
        level = presentationWindowLevel
        collectionBehavior = presentationCollectionBehavior
        allowsPresentationFrameOutsideVisibleArea = true
    }

    private func restoreDefaultWindowMode() {
        level = defaultWindowLevel
        collectionBehavior = defaultCollectionBehavior
        allowsPresentationFrameOutsideVisibleArea = false
    }

    private func installContentView() {
        let shorter: CGFloat
        if settings.cameraCustomSizePt > 0 {
            shorter = CGFloat(settings.cameraCustomSizePt)
        } else {
            shorter = settings.cameraSize.shorterDimension
        }

        let view = CameraPiPView(
            cameraManager: cameraManager,
            shorterDimension: shorter,
            shape: isPresentationMode ? .square : settings.cameraShape,
            mirror: settings.cameraMirror,
            usePresentationChrome: isPresentationMode,
            forcedSize: isPresentationMode ? self.frame.size : nil
        )
        self.contentView = NSHostingView(rootView: view)
    }
}
