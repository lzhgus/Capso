// App/Sources/QuickAccess/QuickAccessWindow.swift
import AppKit
import SwiftUI
import CaptureKit
import SharedKit
import ShareKit

@MainActor
final class QuickAccessWindow: NSPanel {
    private static let cornerRadius: CGFloat = 14
    private static let dismissalEdgeInset: CGFloat = 8

    override var canBecomeKey: Bool { true }

    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onSaveAs: (() -> Void)?
    var onAnnotate: (() -> Void)?
    var onOCR: (() -> Void)?
    var onTranslate: (() -> Void)?
    var onPin: (() -> Void)?
    var onPreview: (() -> Void)?
    var onClose: (() -> Void)?
    var onDismissedUnused: (() -> Void)?
    /// Called with the public URL string when a cloud upload succeeds.
    var onUploadSucceeded: ((String) -> Void)?

    private var autoDismissTimer: Timer?
    private var alphaValueBeforeDrag: CGFloat?
    private var transitionWindow: QuickAccessTransitionWindow?
    private var closeAnimationID = UUID()
    private var isClosing = false
    private var anchoredPosition: QuickAccessPosition
    private let settings: AppSettings
    private let transitionImage: NSImage
    /// The screen this preview is anchored to (where the capture originated).
    let targetScreen: NSScreen

    init(
        result: CaptureResult,
        settings: AppSettings,
        screen: NSScreen?,
        shareCoordinator: ShareCoordinator?,
        autoUpload: Bool
    ) {
        self.settings = settings
        self.anchoredPosition = settings.quickAccessPosition
        self.targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!
        // Keep a Retina-sized display texture; actions still receive the original capture.
        let displayScale = max(2, targetScreen.backingScaleFactor)
        // Match the view's centered aspect-fill crop before downsampling, so
        // panoramic and portrait captures do not get enlarged from a thin strip.
        let imageWidth = CGFloat(result.image.width)
        let imageHeight = CGFloat(result.image.height)
        let cropWidth = min(imageWidth, imageHeight * 268 / 142)
        let cropHeight = min(imageHeight, imageWidth * 142 / 268)
        let cropped = result.image.cropping(to: CGRect(
            x: (imageWidth - cropWidth) / 2,
            y: (imageHeight - cropHeight) / 2,
            width: cropWidth,
            height: cropHeight
        )) ?? result.image
        let thumbnail = ImageUtilities.scaled(
            cropped,
            maxWidth: Int(268 * displayScale),
            maxHeight: Int(142 * displayScale)
        ) ?? result.image
        self.transitionImage = NSImage(cgImage: thumbnail, size: NSSize(
            width: thumbnail.width,
            height: thumbnail.height
        ))

        let windowWidth: CGFloat = 288
        let windowHeight: CGFloat = 200

        let contentRect = QuickAccessStackGeometry.frame(
            position: settings.quickAccessPosition,
            screenFrame: targetScreen.frame,
            visibleFrame: targetScreen.visibleFrame,
            windowSize: CGSize(width: windowWidth, height: windowHeight),
            stackIndex: 0,
            stackCount: 1
        )

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.isMovableByWindowBackground = true
        self.animationBehavior = .utilityWindow
        self.hidesOnDeactivate = false

        let nsImage = transitionImage

        let dimensions = "\(result.image.width)×\(result.image.height)"
        let targetDisplay = Self.targetLanguageDisplay(settings: settings)

        let view = QuickAccessView(
            thumbnail: nsImage,
            captureImage: result.image,
            dimensions: dimensions,
            capturedAt: result.timestamp,
            sourceAppName: result.appName,
            sourceWindowTitle: result.windowName,
            screenshotOutput: settings.screenshotOutputOptions,
            screenshotFilenameTemplate: settings.screenshotFilenameTemplate,
            targetLanguageDisplay: targetDisplay,
            shareCoordinator: shareCoordinator,
            autoUpload: autoUpload,
            onUploadSucceeded: { [weak self] url in self?.onUploadSucceeded?(url) },
            onCopy:      { [weak self] in self?.onCopy?() },
            onSave:      { [weak self] in self?.onSave?() },
            onSaveAs:    { [weak self] in self?.onSaveAs?() },
            onAnnotate:  { [weak self] in self?.onAnnotate?() },
            onOCR:       { [weak self] in self?.onOCR?() },
            onTranslate: { [weak self] in self?.onTranslate?() },
            onPin:       { [weak self] in self?.onPin?() },
            onPreview:   { [weak self] in self?.onPreview?() },
            onDragStarted: { [weak self] in self?.hideDuringExternalDrag() },
            onDragEnded:   { [weak self] dropped in self?.finishExternalDrag(dropped: dropped) },
            onHoverChanged: { [weak self] hovering in self?.hoverChanged(hovering) },
            onClose:     { [weak self] in self?.onClose?() }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = Self.cornerRadius
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true

        self.contentView = hostingView
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private static func targetLanguageDisplay(settings: AppSettings) -> String? {
        let target = settings.translationTargetLanguage
        return Locale.current.localizedString(forIdentifier: target) ?? target
    }

    private func hideDuringExternalDrag() {
        guard !isClosing, alphaValueBeforeDrag == nil else { return }
        stopAutoDismissTimer()
        alphaValueBeforeDrag = alphaValue
        alphaValue = 0
        ignoresMouseEvents = true
    }

    private func finishExternalDrag(dropped: Bool) {
        guard !isClosing else { return }
        if dropped && settings.quickAccessCloseAfterDrag {
            onClose?()
        } else {
            showAfterExternalDrag()
        }
    }

    /// Auto-close waits while the pointer is over the preview, then starts over.
    private func hoverChanged(_ hovering: Bool) {
        guard !isClosing, alphaValueBeforeDrag == nil else { return }
        if hovering {
            stopAutoDismissTimer()
        } else {
            scheduleAutoDismissTimerIfNeeded()
        }
    }

    private func showAfterExternalDrag() {
        guard !isClosing else { return }
        alphaValue = alphaValueBeforeDrag ?? 1
        alphaValueBeforeDrag = nil
        ignoresMouseEvents = false
        scheduleAutoDismissTimerIfNeeded()
    }

    func show(from sourceFrame: NSRect? = nil) {
        resetDismissalContentTransform()
        let finalFrame = frame
        isClosing = false
        closeAnimationID = UUID()
        ignoresMouseEvents = false
        alphaValueBeforeDrag = nil

        guard let sourceFrame, !sourceFrame.isEmpty,
              let cardImage = panelSnapshot() else {
            showPanel(from: finalFrame.insetBy(dx: min(120, finalFrame.width * 0.42), dy: min(80, finalFrame.height * 0.42)))
            return
        }

        // Animate one complete card surface. Fitting the card's aspect ratio
        // into the capture rect keeps the card and its thumbnail in a stable
        // proportion even when the captured image is extremely wide or tall.
        let sourceCardFrame = Self.aspectFitFrame(
            size: finalFrame.size,
            inside: sourceFrame
        )
        let transitionWindow = QuickAccessTransitionWindow(
            image: cardImage,
            frame: sourceCardFrame
        )
        self.transitionWindow = transitionWindow
        transitionWindow.show()

        transitionWindow.animate(to: finalFrame) { [weak self, weak transitionWindow] in
            guard let self, let transitionWindow,
                  self.transitionWindow === transitionWindow else { return }
            self.transitionWindow = nil
            transitionWindow.orderOut(nil)
            self.orderFrontRegardless()
            self.makeKey()
            self.alphaValue = 1
            self.scheduleAutoDismissTimerIfNeeded()
        }
    }

    private func showPanel(from startFrame: NSRect) {
        let finalFrame = frame
        setFrame(startFrame, display: false)
        alphaValue = 0
        orderFrontRegardless()
        makeKey()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.42
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.2, 1)
            self.animator().setFrame(finalFrame, display: true)
            self.animator().alphaValue = 1
        }

        scheduleAutoDismissTimerIfNeeded()
    }

    private func panelSnapshot() -> NSImage? {
        guard let contentView else { return nil }
        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            return nil
        }
        bitmap.size = contentView.bounds.size
        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
        let image = NSImage(size: contentView.bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    private static func aspectFitFrame(size: CGSize, inside rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else {
            return rect
        }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fittedSize = CGSize(width: size.width * scale, height: size.height * scale)
        return NSRect(
            x: rect.midX - fittedSize.width / 2,
            y: rect.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    func show() {
        show(from: nil)
    }

    override func close() {
        guard !isClosing else { return }
        isClosing = true
        ignoresMouseEvents = true
        alphaValueBeforeDrag = nil
        let animationID = UUID()
        closeAnimationID = animationID
        stopAutoDismissTimer()

        cancelEntranceTransition()

        let currentFrame = frame
        var endFrame = currentFrame
        let screenFrame = targetScreen.frame
        switch anchoredPosition {
        case .bottomLeft:
            let distance = min(120, currentFrame.width * 0.42)
            let availableDistance = max(0, currentFrame.minX - screenFrame.minX - Self.dismissalEdgeInset)
            endFrame.origin.x -= min(distance, availableDistance)
        case .bottomRight:
            let distance = min(120, currentFrame.width * 0.42)
            let availableDistance = max(0, screenFrame.maxX - Self.dismissalEdgeInset - currentFrame.maxX)
            endFrame.origin.x += min(distance, availableDistance)
        case .centerScreen:
            let distance = min(80, currentFrame.height * 0.42)
            let availableDistance = max(0, currentFrame.minY - screenFrame.minY - Self.dismissalEdgeInset)
            endFrame.origin.y -= min(distance, availableDistance)
        }
        endFrame = Self.frameFitted(endFrame, within: screenFrame)
        guard isVisible, alphaValue > 0 else {
            finishCloseAnimation()
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animateDismissalContent(for: self.anchoredPosition, duration: ctx.duration)
            self.animator().setFrame(endFrame, display: false)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.closeAnimationID == animationID else { return }
            self.finishCloseAnimation()
        })
    }

    private func finishCloseAnimation() {
        super.close()
    }

    private static func frameFitted(_ frame: NSRect, within bounds: NSRect) -> NSRect {
        let size = NSSize(
            width: min(frame.width, bounds.width),
            height: min(frame.height, bounds.height)
        )
        return NSRect(
            x: min(max(frame.minX, bounds.minX), bounds.maxX - size.width),
            y: min(max(frame.minY, bounds.minY), bounds.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    private func animateDismissalContent(for position: QuickAccessPosition, duration: TimeInterval) {
        guard let layer = contentView?.layer else { return }

        let transform: CGAffineTransform
        switch position {
        case .bottomLeft:
            transform = CGAffineTransform(translationX: -32, y: 0).scaledBy(x: 0.78, y: 1)
        case .bottomRight:
            transform = CGAffineTransform(translationX: 32, y: 0).scaledBy(x: 0.78, y: 1)
        case .centerScreen:
            transform = CGAffineTransform(translationX: 0, y: -24).scaledBy(x: 1, y: 0.75)
        }

        let finalTransform = CATransform3DMakeAffineTransform(transform)
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = layer.presentation()?.transform ?? layer.transform
        animation.toValue = finalTransform
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.transform = finalTransform
        layer.add(animation, forKey: "quickAccessDismissal")
    }

    private func resetDismissalContentTransform() {
        guard let layer = contentView?.layer else { return }
        layer.removeAnimation(forKey: "quickAccessDismissal")
        layer.transform = CATransform3DIdentity
    }

    private func cancelEntranceTransition() {
        let transitionWindow = self.transitionWindow
        self.transitionWindow = nil
        transitionWindow?.orderOut(nil)
    }

    /// Evict this preview off-screen to the left with a slide animation.
    func slideOffLeftAndClose() {
        guard !isClosing else { return }
        isClosing = true
        ignoresMouseEvents = true
        alphaValueBeforeDrag = nil
        let animationID = UUID()
        closeAnimationID = animationID
        stopAutoDismissTimer()
        cancelEntranceTransition()
        var target = frame
        target.origin.x = -(target.width + 40)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.38
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().setFrame(target, display: true)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.closeAnimationID == animationID else { return }
            self.orderOut(nil)
        })
    }

    /// Reposition this window within a stack, centering the group when requested.
    func repositionForStack(index: Int, count: Int, animated: Bool = true) {
        guard !isClosing else { return }
        anchoredPosition = settings.quickAccessPosition
        let newFrame = QuickAccessStackGeometry.frame(
            position: anchoredPosition,
            screenFrame: targetScreen.frame,
            visibleFrame: targetScreen.visibleFrame,
            windowSize: frame.size,
            stackIndex: index,
            stackCount: count
        )

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: true)
        }
    }

    private func scheduleAutoDismissTimerIfNeeded() {
        stopAutoDismissTimer()
        guard !isClosing, alphaValueBeforeDrag == nil, settings.quickAccessAutoClose else { return }

        autoDismissTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(settings.quickAccessAutoCloseInterval),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isClosing, self.alphaValueBeforeDrag == nil else { return }
                self.onClose?()
            }
        }
    }

    private func stopAutoDismissTimer() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
    }
}

@MainActor
private final class QuickAccessTransitionWindow: NSPanel {
    private let imageView: NSImageView

    init(image: NSImage, frame: NSRect) {
        imageView = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 14
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        contentView = imageView
    }

    func show() {
        alphaValue = 1
        orderFrontRegardless()
    }

    func animate(to targetFrame: NSRect, completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.48
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.75, 0.2, 1)
            animator().setFrame(targetFrame, display: true)
        }, completionHandler: completion)
    }
}
