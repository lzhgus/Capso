// App/Sources/Capture/CaptureOverlayWindow.swift
import AppKit
import CaptureKit
import SharedKit

@MainActor
final class CaptureOverlayWindow: NSPanel {
    var onAreaSelected: ((CGRect, NSScreen) -> Void)?
    var onWindowSelected: ((CGWindowID) -> Void)?
    var onCancelled: (() -> Void)?

    private let settings: AppSettings
    private var overlayView: CaptureOverlayView!
    private var globalEscMonitor: Any?
    private var localEscMonitor: Any?

    init(screen: NSScreen, settings: AppSettings, presetsDisabled: Bool = false) {
        self.settings = settings
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.isMovable = false
        self.acceptsMouseMovedEvents = true
        self.hidesOnDeactivate = false

        // Prevent this window from causing app activation changes
        let preventsActivationSel = NSSelectorFromString("_setPreventsActivation:")
        if responds(to: preventsActivationSel) {
            perform(preventsActivationSel, with: NSNumber(value: true))
        }

        let screenID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        overlayView = CaptureOverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            settings: settings,
            presetsDisabled: presetsDisabled,
            screenID: screenID
        )
        overlayView.onSelectionComplete = { [weak self] rect in
            guard let self, let screen = self.screen else { return }
            self.onAreaSelected?(rect, screen)
        }
        overlayView.onWindowSelected = { [weak self] windowID in
            self?.onWindowSelected?(windowID)
        }
        overlayView.onCancel = { [weak self] in
            self?.onCancelled?()
        }

        self.contentView = overlayView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func activate(mode: CaptureOverlayMode = .area) {
        overlayView.setMode(mode)
        overlayView.resetSelection()

        // Show the window. Non-activating panel won't activate our app.
        orderFrontRegardless()

        // Make this window key so it receives keyboard events (ESC).
        // On a .nonactivatingPanel, makeKey() does NOT activate the app.
        makeKey()
        makeFirstResponder(overlayView)

        // Prime the reticle/cursor only after the window is visible and key.
        // Doing this earlier can leave the first frame using a stale or zero
        // cursor position until the user moves the mouse.
        overlayView.prepareForPresentation()

        // Also install global ESC monitor as fallback
        // (in case the window doesn't receive key events)
        installEscMonitor()
    }

    func setFrozenBackground(_ image: CGImage) {
        overlayView.frozenBackground = image
        // Pre-render the frozen image into the view's backing store
        overlayView.needsDisplay = true
        overlayView.displayIfNeeded()
    }

    func deactivate() {
        overlayView.restoreCursorIfNeeded()
        removeEscMonitor()
        orderOut(nil)
    }

    private func installEscMonitor() {
        // Global monitor: catches ESC even when another app is frontmost
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async {
                    self?.onCancelled?()
                }
            }
        }
        // Local monitor: catches ESC when our window is key
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.onCancelled?()
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let globalEscMonitor {
            NSEvent.removeMonitor(globalEscMonitor)
            self.globalEscMonitor = nil
        }
        if let localEscMonitor {
            NSEvent.removeMonitor(localEscMonitor)
            self.localEscMonitor = nil
        }
    }
}
