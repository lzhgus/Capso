// App/Sources/Capture/CaptureCoordinator.swift
import AppKit
import CoreImage
import Observation
import UserNotifications
import AnnotationKit
import CaptureKit
import OCRKit
import SharedKit
import ShareKit

@MainActor
@Observable
final class CaptureCoordinator {
    private let settings: AppSettings
    private var overlayWindows: [CaptureOverlayWindow] = []
    /// Stack of active preview windows:
    /// - `[0]` is the OLDEST preview, anchored at the bottom-left primary slot
    /// - `[N]` is the NEWEST preview, sitting at the top of the visual stack
    /// - New captures append to the end, growing the stack upward
    /// - When the stack overflows, `[0]` (the oldest) slides off-screen to
    ///   the left and the rest shift down one slot
    private var quickAccessWindows: [QuickAccessWindow] = []
    /// Maximum previews kept on-screen. Oldest is evicted when exceeded.
    private let maxQuickAccessStackSize = 5
    private var annotationWindow: AnnotationEditorWindow?
    private var pinnedControllers: [PinnedScreenshotController] = []
    /// Opaque freeze-screen windows (one per display) that replace the live desktop
    private var freezeWindows: [NSWindow] = []
    private var scrollCaptureController: ScrollCaptureController?
    private var scrollCaptureOverlay: ScrollCaptureOverlay?

    var lastCaptureResult: CaptureResult?
    var ocrCoordinator: OCRCoordinator?
    var translationCoordinator: TranslationCoordinator?
    var historyCoordinator: HistoryCoordinator?
    var shareCoordinator: ShareCoordinator?

    /// Post-capture action override. When set, ignores Settings toggles.
    private var pendingAction: PostCaptureAction = .default

    enum PostCaptureAction {
        case `default`    // Use Settings (Show Preview / Copy / Auto Save)
        case clipboard    // Copy to clipboard only, no preview
        case annotate     // Open annotation editor directly
        case share        // Upload to cloud, skip Quick Access, save to history
    }

    init(settings: AppSettings) {
        self.settings = settings
    }

    func captureArea() {
        pendingAction = .default
        startAreaCapture()
    }

    func captureAreaToClipboard() {
        pendingAction = .clipboard
        startAreaCapture()
    }

    func captureAreaAndAnnotate() {
        pendingAction = .annotate
        startAreaCapture()
    }

    func captureAreaAndShare() {
        // Gate: Cloud Share not configured → ask AppDelegate (via notification) to
        // open Preferences → Cloud Share tab. We avoid `NSApp.delegate as? AppDelegate`
        // because the cast fails under SwiftUI's @NSApplicationDelegateAdaptor proxying.
        guard let coord = shareCoordinator else {
            NotificationCenter.default.post(
                name: .openScreenshotSettings,
                object: PreferencesTab.cloudShare
            )
            return
        }

        // Gate: upload already in flight → notify and bail
        if case .uploading = coord.state {
            Self.postNotification(
                title: String(localized: "Cloud Share busy"),
                body: String(localized: "Previous upload still in progress — try again in a moment.")
            )
            return
        }

        // All clear: run area selection, upload on success
        pendingAction = .share
        startAreaCapture()
    }

    private func startAreaCapture() {
        if settings.freezeScreen {
            showFrozenOverlay()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.showOverlay()
            }
        }
    }

    func captureFullscreen() {
        // Capture the display the user is currently looking at (the one
        // containing the mouse cursor), not unconditionally the primary.
        // For keyboard-shortcut invocations this matches where attention is;
        // for menu-bar clicks the mouse is on the screen whose menu bar was
        // clicked. Fall back to `NSScreen.main` then the primary CGDisplay
        // so we never end up with no target at all.
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
        let displayID = targetScreen?.displayID ?? CGMainDisplayID()
        Task {
            do {
                let result = try await ScreenCaptureManager.captureFullscreen(displayID: displayID)
                handleCaptureResult(result)
            } catch {
                print("Fullscreen capture failed: \(error)")
            }
        }
    }

    func captureScrolling() {
        // Use area selection overlay, then start scrolling capture on the selected region
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.showOverlay(mode: .area, isScrollingCapture: true)
        }
    }

    func captureWindow() {
        // Enumerate windows first, then show overlay in window selection mode
        Task {
            do {
                // Exclude only Capso's overlay windows (not all Capso windows
                // like Settings) so the user can still capture them.
                let overlayIDs = Set(overlayWindows.map { CGWindowID($0.windowNumber) })
                let windows = try await ContentEnumerator.windows()
                    .filter { !overlayIDs.contains($0.id) }

                guard !windows.isEmpty else {
                    print("No windows found to capture")
                    return
                }

                showOverlay(mode: .windowSelection(windows))
            } catch {
                print("Window enumeration failed: \(error)")
            }
        }
    }

    private func showOverlay(mode: CaptureOverlayMode = .area, isScrollingCapture: Bool = false) {
        dismissOverlay()
        for screen in NSScreen.screens {
            let overlay = CaptureOverlayWindow(screen: screen, settings: settings)
            overlay.onAreaSelected = { [weak self] rect, screen in
                self?.dismissOverlay()
                if isScrollingCapture {
                    self?.startScrollingCapture(rect: rect, screen: screen)
                } else {
                    self?.performAreaCapture(rect: rect, screen: screen)
                }
            }
            overlay.onWindowSelected = { [weak self] windowID in
                self?.dismissOverlay()
                self?.performWindowCapture(windowID: windowID)
            }
            overlay.onCancelled = { [weak self] in
                self?.dismissOverlay()
            }
            overlay.activate(mode: mode)
            overlayWindows.append(overlay)
        }
    }

    /// Two-window freeze architecture for preserving popups/dropdowns:
    ///
    /// 1. Bottom window: OPAQUE, shows frozen image, completely replaces the
    ///    live desktop. isOpaque=true means no compositing with what's behind
    ///    → no sub-pixel mismatch → no shaking. Pre-rendered before showing.
    ///
    /// 2. Top window: TRANSPARENT overlay for crosshair + selection + dark tint.
    private func showFrozenOverlay() {
        dismissOverlay()

        var frozenScreens: [(NSScreen, CGImage)] = []
        for screen in NSScreen.screens {
            if let image = Self.syncCaptureDisplay(screen.displayID) {
                frozenScreens.append((screen, image))
            }
        }

        guard !frozenScreens.isEmpty else {
            showOverlay()
            return
        }

        // Step 1: Create opaque freeze windows (bottom layer)
        for (screen, frozenImage) in frozenScreens {
            let freezeWin = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            freezeWin.level = .screenSaver - 1
            freezeWin.isOpaque = true
            freezeWin.hasShadow = false
            freezeWin.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            freezeWin.hidesOnDeactivate = false

            let imageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            imageView.image = NSImage(cgImage: frozenImage, size: screen.frame.size)
            imageView.imageScaling = .scaleAxesIndependently
            freezeWin.contentView = imageView

            // Pre-render and show
            freezeWin.displayIfNeeded()
            freezeWin.orderFrontRegardless()
            freezeWindows.append(freezeWin)
        }

        // Step 2: Create transparent overlay windows (top layer) for selection
        for (screen, frozenImage) in frozenScreens {
            let overlay = CaptureOverlayWindow(screen: screen, settings: settings)
            overlay.onAreaSelected = { [weak self] rect, screen in
                self?.dismissOverlay()
                let screenFrame = screen.frame
                let scaleX = CGFloat(frozenImage.width) / screenFrame.width
                let scaleY = CGFloat(frozenImage.height) / screenFrame.height
                let cropRect = CGRect(
                    x: rect.origin.x * scaleX,
                    y: (screenFrame.height - rect.origin.y - rect.height) * scaleY,
                    width: rect.width * scaleX,
                    height: rect.height * scaleY
                )
                if let cropped = frozenImage.cropping(to: cropRect) {
                    let result = CaptureResult(
                        image: cropped,
                        mode: .area,
                        captureRect: rect,
                        displayID: screen.displayID
                    )
                    self?.handleCaptureResult(result)
                }
            }
            overlay.onCancelled = { [weak self] in
                self?.dismissOverlay()
            }
            overlay.activate(mode: .area)
            overlayWindows.append(overlay)
        }
    }

    private func performWindowCapture(windowID: CGWindowID) {
        Task {
            do {
                // Always capture without system shadow — we generate our own
                // uniform padding + frosted glass backdrop when the setting is on.
                let result = try await ScreenCaptureManager.captureWindow(
                    windowID: windowID,
                    includeShadow: false
                )
                if settings.captureWindowShadow {
                    // Capture the real desktop behind the window (excluding the
                    // window itself) for the frosted glass background.
                    // Padding = 4% of the shorter side, plus room for shadow blur.
                    let shorter = min(CGFloat(result.image.width), CGFloat(result.image.height))
                    let padding = max(30, shorter * 0.04)
                    let totalPadding = padding + 20 // extra for shadow spread
                    let desktopBg = try await ScreenCaptureManager.captureDesktopBehindWindow(
                        windowID: windowID,
                        padding: totalPadding
                    )
                    if let composited = Self.compositeWindowWithFrostedGlass(
                        windowImage: result.image,
                        desktopBackground: desktopBg
                    ) {
                        let enhanced = CaptureResult(
                            image: composited,
                            mode: result.mode,
                            captureRect: result.captureRect,
                            windowName: result.windowName,
                            appName: result.appName,
                            appBundleIdentifier: result.appBundleIdentifier,
                            timestamp: result.timestamp,
                            displayID: result.displayID
                        )
                        handleCaptureResult(enhanced)
                        return
                    }
                }
                handleCaptureResult(result)
            } catch {
                print("Window capture failed: \(error)")
            }
        }
    }

    /// Composite a window screenshot over a frosted-glass version of the real
    /// desktop background, with uniform padding, rounded corners, and a soft
    /// drop shadow.
    private static func compositeWindowWithFrostedGlass(
        windowImage: CGImage,
        desktopBackground: CGImage
    ) -> CGImage? {
        let outW = desktopBackground.width
        let outH = desktopBackground.height
        guard outW > 0, outH > 0 else { return nil }

        let imgW = CGFloat(windowImage.width)
        let imgH = CGFloat(windowImage.height)
        let canvasSize = CGSize(width: outW, height: outH)
        let shadowRadius: CGFloat = 20
        let cornerRadius: CGFloat = 12

        // Centre the window in the canvas
        let offsetX = (CGFloat(outW) - imgW) / 2
        let offsetY = (CGFloat(outH) - imgH) / 2
        let imageRect = CGRect(x: offsetX, y: offsetY, width: imgW, height: imgH)
        let roundedPath = CGPath(roundedRect: imageRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // --- Blur the desktop background via CoreImage ---
        guard let backdrop = frostedGlassBackdrop(from: desktopBackground, targetSize: canvasSize) else { return nil }

        // --- Composite ---
        guard let ctx = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: outW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let canvasRect = CGRect(x: 0, y: 0, width: outW, height: outH)

        // 1. Draw frosted desktop backdrop
        ctx.draw(backdrop, in: canvasRect)

        // 2. Draw soft shadow — clip to OUTSIDE the rounded rect so the
        //    white fill used to generate the shadow never bleeds into the
        //    corner area (which would show as white corner artifacts).
        ctx.saveGState()
        let outerPath = CGMutablePath()
        outerPath.addRect(canvasRect)
        outerPath.addPath(roundedPath)
        ctx.addPath(outerPath)
        ctx.clip(using: .evenOdd)
        ctx.setShadow(
            offset: CGSize(width: 0, height: -4),
            blur: shadowRadius,
            color: NSColor.black.withAlphaComponent(0.25).cgColor
        )
        ctx.addPath(roundedPath)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // 3. Draw window clipped to rounded corners
        ctx.saveGState()
        ctx.addPath(roundedPath)
        ctx.clip()
        ctx.draw(windowImage, in: imageRect)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    /// Blur and slightly saturate a desktop background image for the frosted
    /// glass effect behind window captures.
    private static func frostedGlassBackdrop(from image: CGImage, targetSize: CGSize) -> CGImage? {
        let srcW = CGFloat(image.width)
        let srcH = CGFloat(image.height)
        guard srcW > 0, srcH > 0 else { return nil }

        var ci = CIImage(cgImage: image)

        // Aspect-fill to target size with slight overshoot to avoid blur edges.
        let coverScale = max(targetSize.width / srcW, targetSize.height / srcH) * 1.05
        ci = ci.transformed(by: CGAffineTransform(scaleX: coverScale, y: coverScale))
        let tx = (targetSize.width - ci.extent.width) / 2 - ci.extent.minX
        let ty = (targetSize.height - ci.extent.height) / 2 - ci.extent.minY
        ci = ci.transformed(by: CGAffineTransform(translationX: tx, y: ty))

        // Boost saturation slightly for richer colours.
        if let f = CIFilter(name: "CIColorControls", parameters: [
            kCIInputImageKey: ci,
            kCIInputSaturationKey: 1.4,
            kCIInputBrightnessKey: 0.0,
            kCIInputContrastKey: 0.98,
        ]), let out = f.outputImage {
            ci = out
        }

        // Heavy Gaussian blur for frosted glass look.
        let clamped = ci.clampedToExtent()
        if let f = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: clamped,
            kCIInputRadiusKey: 80.0,
        ]), let out = f.outputImage {
            ci = out
        }

        let ciCtx = CIContext(options: nil)
        return ciCtx.createCGImage(ci, from: CGRect(origin: .zero, size: targetSize))
    }

    private func dismissOverlay() {
        for window in overlayWindows {
            window.deactivate()
        }
        overlayWindows.removeAll()

        // Fade out freeze windows smoothly instead of instant removal
        let windows = freezeWindows
        freezeWindows.removeAll()
        if windows.isEmpty { return }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            for window in windows {
                window.animator().alphaValue = 0
            }
        }
        // Clean up after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            for window in windows {
                window.orderOut(nil)
            }
        }
    }

    // MARK: - Scrolling Capture

    /// Saved capture rect (ScreenCaptureKit coordinates) for deferred start.
    private var scrollCaptureRect: CGRect = .zero
    private var scrollCaptureDisplayID: CGDirectDisplayID = 0

    private func startScrollingCapture(rect: CGRect, screen: NSScreen) {
        let screenFrame = screen.frame
        // Convert from bottom-left (NSView) to top-left (ScreenCaptureKit) coordinates
        scrollCaptureRect = CGRect(
            x: rect.origin.x,
            y: screenFrame.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        scrollCaptureDisplayID = screen.displayID

        // Show persistent overlay: selection border + controls + preview
        let overlay = ScrollCaptureOverlay()
        self.scrollCaptureOverlay = overlay

        overlay.onStart = { [weak self] in
            self?.beginScrollingCaptureLoop()
        }

        overlay.onDone = { [weak self] in
            self?.finishScrollingCapture()
        }

        overlay.onCancel = { [weak self] in
            self?.cancelScrollingCapture()
        }

        overlay.show(selectionRect: rect, screen: screen)
    }

    /// Called when user clicks Start — begins the capture loop.
    private func beginScrollingCaptureLoop() {
        let captureRect = scrollCaptureRect
        let displayID = scrollCaptureDisplayID

        let config = ScrollCaptureConfig(
            captureRect: captureRect,
            displayID: displayID,
            mode: .manual
        )
        let controller = ScrollCaptureController(config: config)
        self.scrollCaptureController = controller

        scrollCaptureOverlay?.setCapturing(true)

        controller.start(
            onProgress: { [weak self] progress in
                Task { @MainActor in
                    if let mergedImage = controller.currentMergedImage {
                        self?.scrollCaptureOverlay?.updatePreview(
                            image: mergedImage,
                            height: progress.currentHeight,
                            frameCount: progress.frameCount
                        )
                    }
                }
            },
            onComplete: { [weak self] image in
                Task { @MainActor in
                    self?.scrollCaptureOverlay?.close()
                    self?.scrollCaptureOverlay = nil
                    self?.scrollCaptureController = nil

                    if let image {
                        let result = CaptureResult(
                            image: image,
                            mode: .scrolling,
                            captureRect: captureRect,
                            displayID: displayID
                        )
                        self?.handleCaptureResult(result)
                    }
                }
            }
        )
    }

    private func finishScrollingCapture() {
        scrollCaptureController?.stop()
    }

    private func cancelScrollingCapture() {
        scrollCaptureController?.stop()
        scrollCaptureOverlay?.close()
        scrollCaptureOverlay = nil
        scrollCaptureController = nil
    }

    private func performAreaCapture(rect: CGRect, screen: NSScreen) {
        Task {
            do {
                let screenFrame = screen.frame
                // rect is already in view-local coords (0..screenWidth, 0..screenHeight, bottom-left origin)
                // Only flip Y for ScreenCaptureKit (top-left origin)
                let screenRect = CGRect(
                    x: rect.origin.x,
                    y: screenFrame.height - rect.origin.y - rect.height,
                    width: rect.width,
                    height: rect.height
                )
                let displayID = screen.displayID
                let result = try await ScreenCaptureManager.captureArea(
                    rect: screenRect,
                    displayID: displayID
                )
                handleCaptureResult(result)
            } catch {
                print("Area capture failed: \(error)")
            }
        }
    }

    private func handleCaptureResult(_ result: CaptureResult) {
        lastCaptureResult = result
        if settings.playShutterSound {
            Self.shutterSound?.stop()
            Self.shutterSound?.play()
        }

        let action = pendingAction
        pendingAction = .default

        // Pre-generate the history entry ID so we can wire the cloud URL callback
        // before the async save completes.
        let entryID = UUID()

        switch action {
        case .clipboard:
            copyImageToClipboard(result.image)
        case .annotate:
            // Open the editor on the same screen the capture came from.
            openAnnotationEditor(result, anchorScreen: screenFor(result: result))
        case .share:
            // Skip Quick Access, save to history, then upload in background.
            historyCoordinator?.saveCapture(result: result, entryID: entryID)
            if let coord = shareCoordinator {
                Task { await self.performShareAfterCapture(result: result, entryID: entryID, coord: coord) }
            } else {
                Self.postNotification(
                    title: String(localized: "Cloud share failed"),
                    body: String(localized: "Cloud Share is not configured.")
                )
            }
            return  // history already saved above; skip the call below
        case .default:
            if settings.screenshotAutoCopy {
                copyImageToClipboard(result.image)
            }
            if settings.screenshotAutoSave {
                saveImageToFile(result.image)
            }
            if settings.screenshotShowPreview {
                showQuickAccess(for: result, entryID: entryID)
            }
        }
        historyCoordinator?.saveCapture(result: result, entryID: entryID)
    }

    /// The real camera-shutter sound macOS itself plays for Cmd+Shift+3/4.
    /// Loaded from the built-in CoreAudio system sounds bundle. If the file
    /// ever moves or is renamed in a future macOS release we fall back to a
    /// subtler "Pop" alert sound (which is at least not the "Tink" error
    /// ding we used to use).
    private static let shutterSound: NSSound? = {
        let shutterPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        if FileManager.default.fileExists(atPath: shutterPath),
           let sound = NSSound(contentsOf: URL(fileURLWithPath: shutterPath), byReference: true) {
            return sound
        }
        return NSSound(named: "Pop")
    }()

    private func showQuickAccess(for result: CaptureResult, entryID: UUID) {
        // If the stack is full, evict the oldest (the one anchored at the
        // bottom slot) with a slide-off-left animation. The remaining
        // previews will slide down one slot as part of the restack below.
        while quickAccessWindows.count >= maxQuickAccessStackSize {
            let oldest = quickAccessWindows.removeFirst()
            oldest.slideOffLeftAndClose()
        }

        let captureScreen = NSScreen.screens.first { $0.displayID == result.displayID }
        let window = QuickAccessWindow(result: result, settings: settings, screen: captureScreen, shareCoordinator: shareCoordinator)

        // Persist the cloud URL to history when an upload succeeds from Quick Access.
        window.onUploadSucceeded = { [weak self] urlString in
            self?.historyCoordinator?.setCloudURL(id: entryID, url: urlString)
        }

        // All callbacks capture the specific `window` weakly so the right
        // stack slot gets dismissed — not whichever one happens to be newest.
        window.onCopy = { [weak self, weak window] in
            guard let self, let window else { return }
            self.copyImageToClipboard(result.image)
            self.dismissQuickAccessWindow(window)
        }
        window.onSave = { [weak self, weak window] in
            guard let self, let window else { return }
            self.saveImageToFile(result.image)
            self.dismissQuickAccessWindow(window)
        }
        window.onAnnotate = { [weak self, weak window] in
            guard let self, let window else { return }
            let anchor = window.targetScreen
            self.dismissQuickAccessWindow(window)
            self.openAnnotationEditor(result, anchorScreen: anchor)
        }
        window.onPin = { [weak self, weak window] in
            guard let self, let window else { return }
            let anchor = window.frame
            self.dismissQuickAccessWindow(window)
            self.pinToScreen(result, anchor: anchor)
        }
        window.onOCR = { [weak self, weak window] in
            guard let self, let window else { return }
            let anchor = window.targetScreen
            self.dismissQuickAccessWindow(window)
            self.ocrCoordinator?.startVisualOCR(image: result.image, anchorScreen: anchor)
        }
        window.onTranslate = { [weak self, weak window] in
            guard let self, let window else { return }
            let anchor = window.targetScreen
            self.dismissQuickAccessWindow(window)
            self.translationCoordinator?.translate(image: result.image, anchorScreen: anchor)
        }
        window.onClose = { [weak self, weak window] in
            guard let self, let window else { return }
            self.dismissQuickAccessWindow(window)
        }

        quickAccessWindows.append(window)
        restackQuickAccessWindows(excluding: window)
        window.show()
    }

    /// Remove a specific preview from the stack and close it, then slide the
    /// remaining previews on the same screen down to collapse the gap.
    private func dismissQuickAccessWindow(_ window: QuickAccessWindow) {
        guard let idx = quickAccessWindows.firstIndex(where: { $0 === window }) else {
            return
        }
        quickAccessWindows.remove(at: idx)
        window.close()
        restackQuickAccessWindows()
    }

    /// Reposition all preview windows using per-screen stacking: windows on
    /// the same screen share a stack (index 0 at the bottom, 1 above it, …),
    /// independent of windows on other screens.
    ///
    /// - Parameter skipAnimation: A window to position without animation
    ///   (used for the newly-created preview so it appears at the correct
    ///   slot immediately before its show() fade-in).
    private func restackQuickAccessWindows(excluding skipAnimation: QuickAccessWindow? = nil) {
        // Group windows by their target screen's displayID, preserving order
        // (oldest → newest within each group) so the oldest sits at index 0.
        var perScreen: [CGDirectDisplayID: [QuickAccessWindow]] = [:]
        for win in quickAccessWindows {
            let id = win.targetScreen.displayID
            perScreen[id, default: []].append(win)
        }
        for (_, windows) in perScreen {
            for (i, win) in windows.enumerated() {
                let animated = (win !== skipAnimation)
                win.repositionForStackIndex(i, animated: animated)
            }
        }
    }

    private func openAnnotationEditor(_ result: CaptureResult, anchorScreen: NSScreen? = nil) {
        // If the caller didn't pass a screen explicitly, derive one from the
        // capture's displayID so `captureAreaAndAnnotate()` (direct ⌘⇧…
        // shortcut path) also opens on the right display.
        let screen = anchorScreen ?? screenFor(result: result)
        annotationWindow = AnnotationEditorWindow(
            image: result.image,
            anchorScreen: screen,
            onSave: { [weak self] (rendered: CGImage) in
                self?.saveRenderedImage(rendered)
                self?.annotationWindow = nil
            },
            onCopy: { [weak self] (rendered: CGImage) in
                self?.copyRenderedImage(rendered)
                self?.annotationWindow = nil
            },
            onClose: { [weak self] in
                self?.annotationWindow = nil
            }
        )
        annotationWindow?.show()
    }

    /// Look up the NSScreen whose displayID matches the capture. Returns nil
    /// if the originating display is no longer connected (rare — user
    /// unplugged the monitor between capture and action).
    private func screenFor(result: CaptureResult) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == result.displayID }
    }

    /// If the currently-focused Quick Access panel can handle the Translate
    /// action, fire it and return true. Otherwise return false so the caller
    /// (a global shortcut handler) can fall through to its default behavior.
    ///
    /// This exists because the `KeyboardShortcuts` package registers a
    /// SYSTEM-wide hotkey for `⌘⇧T`, which always wins over a SwiftUI
    /// `.keyboardShortcut` attached to the Translate button in the Quick
    /// Access panel. Without this fall-through, pressing ⌘⇧T while hovering
    /// a Quick Access preview would trigger a fresh capture-and-translate
    /// flow instead of translating the capture the user was already looking at.
    @discardableResult
    func invokeQuickAccessTranslateIfKey() -> Bool {
        guard let key = NSApp.keyWindow as? QuickAccessWindow,
              quickAccessWindows.contains(where: { $0 === key }),
              let handler = key.onTranslate else {
            return false
        }
        handler()
        return true
    }

    private func pinToScreen(_ result: CaptureResult, anchor: CGRect) {
        let controller = PinnedScreenshotController(
            image: result.image,
            anchorRect: anchor,
            onCopy: { [weak self] in
                self?.copyImageToClipboard(result.image)
            },
            onSave: { [weak self] in
                self?.saveImageToFile(result.image)
            },
            onDidClose: { [weak self] controllerID in
                self?.pinnedControllers.removeAll { $0.id == controllerID }
            }
        )
        pinnedControllers.append(controller)
        controller.show()
    }

    private func copyImageToClipboard(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        pasteboard.writeObjects([nsImage])
    }

    private func saveImageToFile(_ image: CGImage) {
        let format = settings.screenshotFormat
        let fileFormat: FileFormat = format == .png ? .png : .jpeg
        let url = FileNaming.generateFileURL(
            in: settings.exportLocation,
            type: .screenshot,
            format: fileFormat
        )
        let data: Data? = switch format {
        case .png: ImageUtilities.pngData(from: image)
        case .jpeg: ImageUtilities.jpegData(from: image)
        }
        if let data { try? data.write(to: url) }
    }

    private func saveRenderedImage(_ image: CGImage) {
        saveImageToFile(image)
    }

    private func copyRenderedImage(_ image: CGImage) {
        copyImageToClipboard(image)
    }

    // MARK: - Cloud Share Upload

    private func performShareAfterCapture(
        result: CaptureResult,
        entryID: UUID,
        coord: ShareCoordinator
    ) async {
        let image = result.image

        // Encode + write off the main actor so large PNGs don't block the UI.
        let tempURL: URL? = await Task.detached(priority: .userInitiated) { () -> URL? in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("png")
            guard let data = ImageUtilities.pngData(from: image) else { return nil }
            do {
                try data.write(to: url)
                return url
            } catch {
                return nil
            }
        }.value

        guard let tempURL else {
            Self.postNotification(
                title: String(localized: "Cloud share failed"),
                body: String(localized: "Couldn't encode capture for upload.")
            )
            return
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            let url = try await coord.upload(file: tempURL, contentType: "image/png")
            // ShareCoordinator already copied the URL to clipboard on success.
            historyCoordinator?.setCloudURL(id: entryID, url: url.absoluteString)
            Self.postNotification(
                title: String(localized: "Cloud share ready"),
                body: String(localized: "Link copied to clipboard.")
            )
        } catch let err as ShareError {
            Self.postNotification(
                title: String(localized: "Cloud share failed"),
                body: Self.humanizeShareError(err)
            )
        } catch {
            Self.postNotification(
                title: String(localized: "Cloud share failed"),
                body: error.localizedDescription
            )
        }
    }

    private static func humanizeShareError(_ err: ShareError) -> String {
        switch err {
        case .invalidCredentials:
            return String(localized: "Cloud credentials are invalid.")
        case .network(let underlying):
            return String(localized: "Network error: \(underlying)")
        case .quotaExceeded:
            return String(localized: "Cloud quota exceeded.")
        case .publicAccessUnreachable:
            return String(localized: "Upload OK but public URL unreachable.")
        case .invalidURLPrefix(let reason):
            return String(localized: "Invalid URL prefix: \(reason)")
        case .notConfigured:
            return String(localized: "Cloud Share is not configured.")
        case .unknown(let detail):
            return detail
        }
    }

    /// Post a macOS user notification. Requests authorization on the first call.
    private static func postNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(request, withCompletionHandler: nil)
        }
    }

    // MARK: - Synchronous Display Capture

    /// Synchronously capture a display using CGDisplayCreateImage.
    /// Deprecated in macOS 14+ but still functional — loaded via dlsym
    /// to bypass the compile-time unavailability annotation.
    /// Required for freeze-screen: must capture before any window appears.
    private static func syncCaptureDisplay(_ displayID: CGDirectDisplayID) -> CGImage? {
        typealias CGDisplayCreateImageFunc = @convention(c) (CGDirectDisplayID) -> CGImage?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let sym = dlsym(handle, "CGDisplayCreateImage") else {
            return nil
        }
        defer { dlclose(handle) }
        let fn = unsafeBitCast(sym, to: CGDisplayCreateImageFunc.self)
        return fn(displayID)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? CGMainDisplayID()
    }
}
