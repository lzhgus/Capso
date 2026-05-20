import AppKit
import CaptureKit
import Observation
import SharedKit
import SwiftUI

@MainActor
final class CaptureAllInOneToolbarWindow {
    private static let minimumSelectionSize = CGSize(width: 24, height: 24)
    private static let toolbarCornerRadius: CGFloat = 14

    private var selectionOverlayWindow: NSPanel?
    private weak var selectionOverlayView: AllInOneSelectionOverlayView?
    private var toolbarWindow: NSPanel?
    private var annotationOverlay: CaptureAllInOneAnnotationOverlay?
    private var globalEscMonitor: Any?
    private var localEscMonitor: Any?
    private var globalSelectionMouseMonitor: Any?
    private var localSelectionMouseMonitor: Any?
    private var screenLocalSelectionRect: CGRect
    private let toolbarState: CaptureAllInOneToolbarState
    private let presets: [CapturePreset]
    private var activePreset: CapturePreset
    private let frozenImage: CGImage?
    private var lastLiveAnnotationUpdateTime: TimeInterval = 0

    let screen: NSScreen

    var onPresetChanged: ((CapturePreset) -> Void)?
    var onArea: ((CGRect) -> Void)?
    var onFullscreen: (() -> Void)?
    var onWindow: (() -> Void)?
    var onScrolling: ((CGRect) -> Void)?
    var onTimer: ((CGRect) -> Void)?
    var onOCR: ((CGRect) -> Void)?
    var onRecording: ((CGRect) -> Void)?
    var onAnnotate: ((CGRect) -> Void)?
    var onCopy: ((CGRect) -> Void)?
    var onCopyRendered: ((CGImage, CGRect) -> Void)?
    var onSave: ((CGRect) -> Void)?
    var onSaveRendered: ((CGImage, CGRect) -> Void)?
    var onPin: ((CGRect) -> Void)?
    var onPinRendered: ((CGImage, CGRect) -> Void)?
    var onOCRRendered: ((CGImage, CGRect) -> Void)?
    var onCancel: (() -> Void)?

    init(
        selectionRect: CGRect,
        screen: NSScreen,
        presets: [CapturePreset],
        activePreset: CapturePreset,
        frozenImage: CGImage? = nil
    ) {
        let visiblePresets = presets.isEmpty ? [.freeform] : presets
        self.screenLocalSelectionRect = selectionRect.standardized
        self.presets = visiblePresets
        self.activePreset = activePreset
        self.frozenImage = frozenImage
        self.toolbarState = CaptureAllInOneToolbarState(
            selectionRect: selectionRect.standardized,
            presets: visiblePresets,
            activePreset: activePreset
        )
        self.screen = screen
    }

    func show() {
        screenLocalSelectionRect = CaptureSelectionGeometry.move(
            screenLocalSelectionRect,
            by: .zero,
            in: screenLocalBounds
        )
        updateToolbarState()

        showSelectionOverlay()
        showToolbar()
        showAnnotationOverlayIfPossible()
        installKeyboardMonitor()
    }

    func close() {
        removeKeyboardMonitor()
        annotationOverlay?.close()
        annotationOverlay = nil
        removeSelectionMouseMonitor()
        toolbarWindow?.close()
        toolbarWindow = nil
        selectionOverlayWindow?.close()
        selectionOverlayWindow = nil
        selectionOverlayView = nil
    }

    private var screenLocalBounds: CGRect {
        CGRect(origin: .zero, size: screen.frame.size)
    }

    private var globalSelectionRect: CGRect {
        CGRect(
            x: screenLocalSelectionRect.origin.x + screen.frame.origin.x,
            y: screenLocalSelectionRect.origin.y + screen.frame.origin.y,
            width: screenLocalSelectionRect.width,
            height: screenLocalSelectionRect.height
        )
    }

    private func showSelectionOverlay() {
        let panel = AllInOnePanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onEscape = { [weak self] in self?.onCancel?() }
        panel.level = frozenImage == nil ? .screenSaver : .screenSaver + 2
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let overlayView = AllInOneSelectionOverlayView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            selectionRect: screenLocalSelectionRect,
            minSelectionSize: Self.minimumSelectionSize,
            activePreset: activePreset
        )
        overlayView.passesThroughSelectionBody = frozenImage != nil
        overlayView.onSelectionPreviewChanged = { [weak self] selectionRect in
            self?.updateSelection(selectionRect, phase: .live)
        }
        overlayView.onSelectionChanged = { [weak self] selectionRect in
            self?.updateSelection(selectionRect, phase: .final)
        }
        overlayView.onCancel = { [weak self] in
            self?.onCancel?()
        }
        panel.contentView = overlayView

        selectionOverlayView = overlayView
        selectionOverlayWindow = panel
        panel.orderFrontRegardless()
        panel.makeKey()
        installSelectionMouseMonitorIfNeeded()
    }

    private func showToolbar() {
        let panel = AllInOnePanel(
            contentRect: toolbarFrame(for: globalSelectionRect),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onEscape = { [weak self] in self?.onCancel?() }
        panel.level = frozenImage == nil ? .screenSaver + 1 : .screenSaver + 3
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        panel.acceptsMouseMovedEvents = true

        let hostingView = AllInOneToolbarHostingView(rootView: CaptureAllInOneToolbarView(
            state: toolbarState,
            isSideRail: frozenImage != nil,
            onChromeStateChanged: { [weak self] in
                self?.layoutChrome(animated: true)
            },
            onArea: { [weak self] in
                guard let self else { return }
                self.onArea?(self.screenLocalSelectionRect)
            },
            onFullscreen: { [weak self] in self?.onFullscreen?() },
            onWindow: { [weak self] in self?.onWindow?() },
            onScrolling: { [weak self] in
                guard let self else { return }
                self.onScrolling?(self.screenLocalSelectionRect)
            },
            onTimer: { [weak self] in
                guard let self else { return }
                self.onTimer?(self.screenLocalSelectionRect)
            },
            onOCR: { [weak self] in
                guard let self else { return }
                if let annotationOverlay = self.annotationOverlay {
                    annotationOverlay.renderImage(afterCommit: { [weak self] rendered in
                        guard let self else { return }
                        if let rendered {
                            self.onOCRRendered?(rendered, self.screenLocalSelectionRect)
                        } else {
                            self.onOCR?(self.screenLocalSelectionRect)
                        }
                    })
                } else {
                    self.onOCR?(self.screenLocalSelectionRect)
                }
            },
            onRecording: { [weak self] in
                guard let self else { return }
                self.onRecording?(self.screenLocalSelectionRect)
            },
            onAnnotate: { [weak self] in
                guard let self else { return }
                self.onAnnotate?(self.screenLocalSelectionRect)
            },
            onCopy: { [weak self] in self?.performCopyAction() },
            onSave: { [weak self] in self?.performSaveAction() },
            onPin: { [weak self] in self?.performPinAction() },
            onPresetSelected: { [weak self] preset in
                self?.applyPreset(preset)
            },
            onCancel: { [weak self] in self?.onCancel?() }
        ))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = Self.toolbarCornerRadius
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView

        toolbarWindow = panel
        panel.orderFrontRegardless()
    }

    private func toolbarFrame(for selectionRect: CGRect) -> CGRect {
        if frozenImage != nil {
            return sideRailFrame(for: selectionRect)
        }

        let margin: CGFloat = 12
        let gap: CGFloat = 12
        let toolbarWidth = min(max(980, selectionRect.width), screen.visibleFrame.width - margin * 2)
        let toolbarHeight: CGFloat = 78

        let minX = screen.visibleFrame.minX + margin
        let maxX = screen.visibleFrame.maxX - toolbarWidth - margin
        let x = min(max(selectionRect.midX - toolbarWidth / 2, minX), maxX)

        let belowY = selectionRect.minY - toolbarHeight - gap
        let aboveY = selectionRect.maxY + gap
        let y: CGFloat
        if belowY >= screen.visibleFrame.minY + margin {
            y = belowY
        } else if aboveY + toolbarHeight <= screen.visibleFrame.maxY - margin {
            y = aboveY
        } else {
            y = max(screen.visibleFrame.minY + margin, selectionRect.minY + margin)
        }

        return CGRect(x: x, y: y, width: toolbarWidth, height: toolbarHeight)
    }

    private func sideRailFrame(for selectionRect: CGRect) -> CGRect {
        let margin: CGFloat = 12
        let gap: CGFloat = 10
        let toolbarWidth: CGFloat = 84
        let toolbarHeight = min(toolbarState.preferredRailHeight, screen.visibleFrame.height - margin * 2)

        let preferredRightX = selectionRect.maxX + gap
        let preferredLeftX = selectionRect.minX - toolbarWidth - gap
        let x: CGFloat
        if preferredRightX + toolbarWidth <= screen.visibleFrame.maxX - margin {
            x = preferredRightX
        } else if preferredLeftX >= screen.visibleFrame.minX + margin {
            x = preferredLeftX
        } else {
            x = screen.visibleFrame.maxX - toolbarWidth - margin
        }

        let y = min(
            max(selectionRect.midY - toolbarHeight / 2, screen.visibleFrame.minY + margin),
            screen.visibleFrame.maxY - toolbarHeight - margin
        )

        return CGRect(x: x, y: y, width: toolbarWidth, height: toolbarHeight)
    }

    private enum SelectionUpdatePhase {
        case live
        case final
    }

    private func updateSelection(_ selectionRect: CGRect, phase: SelectionUpdatePhase = .final) {
        screenLocalSelectionRect = CaptureSelectionGeometry.move(
            selectionRect.standardized,
            by: .zero,
            in: screenLocalBounds
        )
        updateToolbarState()
        let isLive = phase == .live
        layoutChrome(animated: !isLive)
        if shouldRefreshAnnotationOverlay(isLive: isLive) {
            updateAnnotationOverlayIfPossible(isLive: isLive)
        }
        updateSelectionMouseHandling()
    }

    private func updateToolbarState() {
        toolbarState.width = max(1, Int(screenLocalSelectionRect.width.rounded()))
        toolbarState.height = max(1, Int(screenLocalSelectionRect.height.rounded()))
        let shouldCompact = frozenImage != nil
            && screenLocalSelectionRect.height < 520
        if toolbarState.isCompact != shouldCompact {
            toolbarState.isCompact = shouldCompact
            toolbarState.showsOverflow = false
        }
    }

    private func applyPreset(_ preset: CapturePreset) {
        activePreset = preset
        toolbarState.activePreset = preset
        selectionOverlayView?.setActivePreset(preset)

        let fittedRect = fittedSelectionRect(for: preset)
        screenLocalSelectionRect = fittedRect
        selectionOverlayView?.setSelectionRect(fittedRect)
        updateToolbarState()
        layoutChrome(animated: true)
        updateAnnotationOverlayIfPossible(isLive: false)
        onPresetChanged?(preset)
    }

    private func layoutChrome(animated: Bool) {
        let frame = toolbarFrame(for: globalSelectionRect)
        if animated {
            toolbarWindow?.setFrame(frame, display: true, animate: true)
        } else {
            toolbarWindow?.setFrame(frame, display: true)
        }
        annotationOverlay?.repositionToolbar(
            selectionRect: screenLocalSelectionRect,
            avoidingFrame: toolbarWindow?.frame,
            animated: animated
        )
    }

    private func showAnnotationOverlayIfPossible() {
        guard let sourceImage = croppedFrozenImage(for: screenLocalSelectionRect) else { return }
        let overlay = CaptureAllInOneAnnotationOverlay(screen: screen)
        annotationOverlay = overlay
        overlay.show(
            sourceImage: sourceImage,
            selectionRect: screenLocalSelectionRect,
            avoidingFrame: toolbarWindow?.frame
        )
    }

    private func updateAnnotationOverlayIfPossible(isLive: Bool) {
        guard let sourceImage = croppedFrozenImage(for: screenLocalSelectionRect) else { return }
        if annotationOverlay == nil {
            let overlay = CaptureAllInOneAnnotationOverlay(screen: screen)
            annotationOverlay = overlay
            overlay.show(
                sourceImage: sourceImage,
                selectionRect: screenLocalSelectionRect,
                avoidingFrame: toolbarWindow?.frame
            )
        } else {
            annotationOverlay?.update(
                sourceImage: sourceImage,
                selectionRect: screenLocalSelectionRect,
                avoidingFrame: toolbarWindow?.frame,
                isLive: isLive
            )
        }
    }

    private func shouldRefreshAnnotationOverlay(isLive: Bool) -> Bool {
        guard isLive else {
            lastLiveAnnotationUpdateTime = 0
            return true
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLiveAnnotationUpdateTime >= 1.0 / 30.0 else {
            return false
        }
        lastLiveAnnotationUpdateTime = now
        return true
    }

    private func croppedFrozenImage(for selectionRect: CGRect) -> CGImage? {
        guard let frozenImage else { return nil }
        let cropRect = CaptureDisplayGeometry.frozenImageCropRect(
            screenLocalRect: selectionRect,
            screenSize: screen.frame.size,
            imageSize: CGSize(width: frozenImage.width, height: frozenImage.height)
        )
        guard !cropRect.isEmpty else { return nil }
        return frozenImage.cropping(to: cropRect)
    }

    private func fittedSelectionRect(for preset: CapturePreset) -> CGRect {
        if let fixedSize = preset.fixedPixelSize {
            return CaptureSelectionGeometry.fixedSize(
                CGSize(width: fixedSize.width, height: fixedSize.height),
                centeredAt: CGPoint(x: screenLocalSelectionRect.midX, y: screenLocalSelectionRect.midY),
                in: screenLocalBounds
            )
        }

        if let ratio = preset.ratio {
            return CaptureSelectionGeometry.fit(
                screenLocalSelectionRect,
                aspectRatio: ratio,
                in: screenLocalBounds,
                minSize: Self.minimumSelectionSize
            )
        }

        return CaptureSelectionGeometry.move(
            screenLocalSelectionRect,
            by: .zero,
            in: screenLocalBounds
        )
    }

    private func performCopyAction() {
        if let annotationOverlay {
            annotationOverlay.renderImage(afterCommit: { [weak self] rendered in
                guard let self else { return }
                if let rendered {
                    self.onCopyRendered?(rendered, self.screenLocalSelectionRect)
                } else {
                    self.onCopy?(self.screenLocalSelectionRect)
                }
            })
        } else {
            onCopy?(screenLocalSelectionRect)
        }
    }

    private func performSaveAction() {
        if let annotationOverlay {
            annotationOverlay.renderImage(afterCommit: { [weak self] rendered in
                guard let self else { return }
                if let rendered {
                    self.onSaveRendered?(rendered, self.screenLocalSelectionRect)
                } else {
                    self.onSave?(self.screenLocalSelectionRect)
                }
            })
        } else {
            onSave?(screenLocalSelectionRect)
        }
    }

    private func performPinAction() {
        if let annotationOverlay {
            annotationOverlay.renderImage(afterCommit: { [weak self] rendered in
                guard let self else { return }
                if let rendered {
                    self.onPinRendered?(rendered, self.screenLocalSelectionRect)
                } else {
                    self.onPin?(self.screenLocalSelectionRect)
                }
            })
        } else {
            onPin?(screenLocalSelectionRect)
        }
    }

    private func installKeyboardMonitor() {
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.onCancel?() }
        }
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyboardEvent(event)
        }
    }

    private func removeKeyboardMonitor() {
        if let globalEscMonitor {
            NSEvent.removeMonitor(globalEscMonitor)
            self.globalEscMonitor = nil
        }
        if let localEscMonitor {
            NSEvent.removeMonitor(localEscMonitor)
            self.localEscMonitor = nil
        }
    }

    private func handleKeyboardEvent(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 {
            onCancel?()
            return nil
        }

        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers == .command else { return event }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            performCopyAction()
            return nil
        case "s":
            performSaveAction()
            return nil
        case "p":
            performPinAction()
            return nil
        default:
            return event
        }
    }

    private func installSelectionMouseMonitorIfNeeded() {
        guard frozenImage != nil else { return }

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalSelectionMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in self?.updateSelectionMouseHandling() }
        }
        localSelectionMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.updateSelectionMouseHandling()
            return event
        }
        updateSelectionMouseHandling()
    }

    private func removeSelectionMouseMonitor() {
        if let globalSelectionMouseMonitor {
            NSEvent.removeMonitor(globalSelectionMouseMonitor)
            self.globalSelectionMouseMonitor = nil
        }
        if let localSelectionMouseMonitor {
            NSEvent.removeMonitor(localSelectionMouseMonitor)
            self.localSelectionMouseMonitor = nil
        }
    }

    private func updateSelectionMouseHandling() {
        guard frozenImage != nil,
              let selectionOverlayWindow,
              let selectionOverlayView else {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let screenLocalPoint = CGPoint(
            x: mouseLocation.x - screen.frame.minX,
            y: mouseLocation.y - screen.frame.minY
        )
        selectionOverlayWindow.ignoresMouseEvents = !selectionOverlayView.wantsMouseEvents(at: screenLocalPoint)
    }
}

private final class AllInOnePanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }

        onEscape?()
    }
}

private final class AllInOneToolbarHostingView<Content: View>: NSHostingView<Content> {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseEntered(with: event)
    }
}

@MainActor
@Observable
private final class CaptureAllInOneToolbarState {
    var width: Int
    var height: Int
    let presets: [CapturePreset]
    var activePreset: CapturePreset
    var isCompact = false
    var showsOverflow = false

    var preferredRailHeight: CGFloat {
        let gap: CGFloat = 7
        let verticalPadding: CGFloat = 20
        let rowHeight: CGFloat = 38
        let presetHeight: CGFloat = 42
        let dimensionHeight: CGFloat = 54
        let dividerHeight: CGFloat = 5

        let itemHeights: [CGFloat]
        if isCompact && !showsOverflow {
            itemHeights = [dimensionHeight, rowHeight, rowHeight, rowHeight, dividerHeight, rowHeight]
        } else {
            itemHeights = [
                rowHeight, rowHeight, rowHeight, rowHeight, rowHeight, rowHeight, rowHeight,
                dividerHeight,
                dimensionHeight,
                presetHeight,
                rowHeight, rowHeight,
                rowHeight
            ]
        }

        return verticalPadding
            + itemHeights.reduce(0, +)
            + CGFloat(max(0, itemHeights.count - 1)) * gap
    }

    init(selectionRect: CGRect, presets: [CapturePreset], activePreset: CapturePreset) {
        self.width = max(1, Int(selectionRect.width.rounded()))
        self.height = max(1, Int(selectionRect.height.rounded()))
        self.presets = presets
        self.activePreset = activePreset
    }
}

private struct CaptureAllInOneToolbarView: View {
    private enum ModeAction: Hashable {
        case area, fullscreen, window, scrolling, timer, ocr, recording
    }

    private enum UtilityAction: Hashable {
        case annotate, copy, save, pin, cancel, overflow
    }

    let state: CaptureAllInOneToolbarState
    let isSideRail: Bool
    let onChromeStateChanged: () -> Void
    let onArea: () -> Void
    let onFullscreen: () -> Void
    let onWindow: () -> Void
    let onScrolling: () -> Void
    let onTimer: () -> Void
    let onOCR: () -> Void
    let onRecording: () -> Void
    let onAnnotate: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onPin: () -> Void
    let onPresetSelected: (CapturePreset) -> Void
    let onCancel: () -> Void

    @State private var hoveredMode: ModeAction?
    @State private var hoveredUtility: UtilityAction?

    var body: some View {
        if isSideRail {
            sideRail
        } else {
            horizontalBar
        }
    }

    private var horizontalBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                modeButton(.area, icon: "viewfinder", title: "Area", action: onArea)
                modeButton(.fullscreen, icon: "display", title: "Fullscreen", action: onFullscreen)
                modeButton(.window, icon: "macwindow", title: "Window", action: onWindow)
                modeButton(.scrolling, icon: "arrow.down.to.line.compact", title: "Scrolling", action: onScrolling)
                modeButton(.timer, icon: "timer", title: "Timer", action: onTimer)
                modeButton(.ocr, textIcon: "Aa", title: "OCR", action: onOCR)
                modeButton(.recording, icon: "video", title: "Recording", action: onRecording)
            }

            divider

            HStack(spacing: 8) {
                dimensionPill
                presetMenu
                iconButton("doc.on.doc", kind: .copy, help: "Copy selected area", action: onCopy)
                iconButton("square.and.arrow.down", kind: .save, help: "Save selected area", action: onSave)
                iconButton("pin", kind: .pin, help: "Pin selected area", action: onPin)
                iconButton("xmark", kind: .cancel, help: "Cancel", action: onCancel)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(toolbarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
        .onHover { hovering in
            if hovering {
                NSCursor.arrow.set()
            }
        }
    }

    private var sideRail: some View {
        VStack(spacing: 7) {
            if !state.isCompact || state.showsOverflow {
                railActionButton(.area, icon: "viewfinder", title: "Area", label: String(localized: "Area"), action: onArea)
                railActionButton(.fullscreen, icon: "display", title: "Fullscreen", label: String(localized: "Full"), action: onFullscreen)
                railActionButton(.window, icon: "macwindow", title: "Window", label: String(localized: "Window"), action: onWindow)
                railActionButton(.scrolling, icon: "arrow.down.to.line.compact", title: "Scrolling", label: String(localized: "Scroll"), action: onScrolling)
                railActionButton(.timer, icon: "timer", title: "Timer", label: String(localized: "Timer"), action: onTimer)
                railActionButton(.ocr, textIcon: "Aa", title: "OCR", label: String(localized: "OCR"), action: onOCR)
                railActionButton(.recording, icon: "video", title: "Recording", label: String(localized: "Record"), action: onRecording)

                railDivider
            }

            railDimensionPill

            if !state.isCompact || state.showsOverflow {
                railPresetMenu
            }

            railIconButton("doc.on.doc", kind: .copy, help: "Copy selected area", label: String(localized: "Copy"), action: onCopy)
            railIconButton("square.and.arrow.down", kind: .save, help: "Save selected area", label: String(localized: "Save"), action: onSave)
            railIconButton("pin", kind: .pin, help: "Pin selected area", label: String(localized: "Pin"), action: onPin)
            railIconButton("xmark", kind: .cancel, help: "Cancel", label: String(localized: "Close"), action: onCancel)

            if state.isCompact {
                railDivider
                railIconButton(
                    state.showsOverflow ? "chevron.up" : "ellipsis",
                    kind: .overflow,
                    help: state.showsOverflow ? "Hide actions" : "More actions",
                    label: state.showsOverflow ? String(localized: "Less") : String(localized: "More"),
                    action: toggleOverflow
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(toolbarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.20, dampingFraction: 0.88), value: state.showsOverflow)
        .onHover { hovering in
            if hovering {
                NSCursor.arrow.set()
            }
        }
    }

    private var toolbarBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.regularMaterial)
            .shadow(color: .black.opacity(0.30), radius: 18, y: 8)
            .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.13))
            .frame(width: 1, height: 44)
    }

    private var railDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.13))
            .frame(width: 42, height: 1)
            .padding(.vertical, 2)
    }

    private var presetMenu: some View {
        Menu {
            ForEach(state.presets) { preset in
                Button {
                    onPresetSelected(preset)
                } label: {
                    if preset == state.activePreset {
                        Label {
                            Text(localizedPresetDisplayName(preset))
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(localizedPresetDisplayName(preset))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(presetLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .frame(width: 74, height: 36)
            .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .help("Capture preset")
    }

    private var railPresetMenu: some View {
        Menu {
            ForEach(state.presets) { preset in
                Button {
                    onPresetSelected(preset)
                } label: {
                    if preset == state.activePreset {
                        Label(localizedPresetDisplayName(preset), systemImage: "checkmark")
                    } else {
                        Text(localizedPresetDisplayName(preset))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(railPresetLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .frame(maxWidth: .infinity)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(width: 60, height: 42)
            .background(Color.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(localizedPresetDisplayName(state.activePreset))
    }

    private var presetLabel: String {
        switch state.activePreset {
        case .freeform:
            return String(localized: "Free")
        case .aspectRatio(let width, let height, _):
            return "\(width):\(height)"
        case .fixedSize(let width, let height, let name):
            return name ?? "\(width)x\(height)"
        }
    }

    private var railPresetLabel: String {
        switch state.activePreset {
        case .freeform:
            return String(localized: "Free")
        case .aspectRatio(let width, let height, _):
            return "\(width):\(height)"
        case .fixedSize(let width, let height, let name):
            if let name, name.count <= 6 {
                return localizedPresetName(name)
            }
            return "\(width)x\(height)"
        }
    }

    private func localizedPresetDisplayName(_ preset: CapturePreset) -> String {
        switch preset {
        case .freeform:
            return String(localized: "Free")
        case .aspectRatio(let width, let height, let name):
            let ratio = "\(width):\(height)"
            if let name {
                return "\(ratio) (\(localizedPresetName(name)))"
            }
            return ratio
        case .fixedSize(let width, let height, let name):
            let size = "\(width) x \(height)"
            if let name {
                return "\(size) (\(localizedPresetName(name)))"
            }
            return size
        }
    }

    private func localizedPresetName(_ name: String) -> String {
        switch name {
        case "Square":
            return String(localized: "Square")
        default:
            return name
        }
    }

    private var dimensionPill: some View {
        Text("\(state.width) x \(state.height)")
        .font(.system(size: 14, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .frame(minWidth: 116, minHeight: 36)
        .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .help("Selected area size")
    }

    private var railDimensionPill: some View {
        VStack(spacing: 1) {
            Text("\(state.width)")
            Text("x")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.58))
            Text("\(state.height)")
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .frame(width: 60, height: 54)
        .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .help("Selected area size")
    }

    private func modeButton(
        _ kind: ModeAction,
        icon: String? = nil,
        textIcon: String? = nil,
        title: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Group {
                    if let textIcon {
                        Text(verbatim: textIcon)
                            .font(.system(size: 15, weight: .bold))
                    } else if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(height: 20)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(.white)
            .frame(width: 78, height: 54)
            .background(modeBackground(kind), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveredMode = $0 ? kind : nil }
        .help(title)
    }

    private func railActionButton(
        _ kind: ModeAction,
        icon: String? = nil,
        textIcon: String? = nil,
        title: LocalizedStringKey,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: hoveredMode == kind ? 1 : 0) {
                Group {
                    if let textIcon {
                        Text(verbatim: textIcon)
                            .font(.system(size: 15, weight: .bold))
                    } else if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(height: hoveredMode == kind ? 17 : 38)

                if hoveredMode == kind {
                    Text(label)
                        .font(.system(size: 8.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(.white)
            .frame(width: 60, height: 38)
            .background(modeBackground(kind), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveredMode = $0 ? kind : nil }
        .help(title)
    }

    private func modeBackground(_ kind: ModeAction) -> Color {
        hoveredMode == kind ? Color.white.opacity(0.12) : Color.white.opacity(0.001)
    }

    private func iconButton(
        _ systemName: String,
        kind: UtilityAction,
        help: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(utilityBackground(kind), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .overlay(alignment: .topTrailing) {
                    if hoveredUtility == kind, let shortcut = utilityShortcut(for: kind) {
                        UtilityShortcutBadge(text: shortcut)
                            .offset(x: 5, y: -5)
                            .transition(.opacity)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hoveredUtility = $0 ? kind : nil }
        .help(utilityHelp(for: kind, fallback: help))
    }

    private func railIconButton(
        _ systemName: String,
        kind: UtilityAction,
        help: LocalizedStringKey,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: hoveredUtility == kind ? 1 : 0) {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(height: hoveredUtility == kind ? 17 : 38)

                if hoveredUtility == kind {
                    Text(label)
                        .font(.system(size: 8.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(.white)
            .frame(width: 60, height: 38)
            .background(utilityBackground(kind), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .overlay(alignment: .topTrailing) {
                if hoveredUtility == kind, let shortcut = utilityShortcut(for: kind) {
                    UtilityShortcutBadge(text: shortcut)
                        .offset(x: 5, y: -5)
                        .transition(.opacity)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hoveredUtility = $0 ? kind : nil }
        .help(utilityHelp(for: kind, fallback: help))
    }

    private func utilityBackground(_ kind: UtilityAction) -> Color {
        hoveredUtility == kind ? Color.white.opacity(0.18) : Color.white.opacity(0.11)
    }

    private func utilityShortcut(for kind: UtilityAction) -> String? {
        switch kind {
        case .copy:
            return "⌘C"
        case .save:
            return "⌘S"
        case .pin:
            return "⌘P"
        case .cancel:
            return "Esc"
        case .annotate, .overflow:
            return nil
        }
    }

    private func utilityHelp(for kind: UtilityAction, fallback: LocalizedStringKey) -> Text {
        guard let shortcut = utilityShortcut(for: kind) else {
            return Text(fallback)
        }

        switch kind {
        case .copy:
            return Text(String(localized: "Copy selected area (\(shortcut))"))
        case .save:
            return Text(String(localized: "Save selected area (\(shortcut))"))
        case .pin:
            return Text(String(localized: "Pin selected area (\(shortcut))"))
        case .cancel:
            return Text(String(localized: "Cancel (\(shortcut))"))
        case .annotate, .overflow:
            return Text(fallback)
        }
    }

    private func toggleOverflow() {
        guard state.isCompact else { return }
        state.showsOverflow.toggle()
        onChromeStateChanged()
    }
}

private struct UtilityShortcutBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(height: 14)
            .background(Color.black.opacity(0.62), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.5))
            .allowsHitTesting(false)
    }
}

private final class AllInOneSelectionOverlayView: NSView {
    var onSelectionPreviewChanged: ((CGRect) -> Void)?
    var onSelectionChanged: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var passesThroughSelectionBody = false

    private enum DragOperation {
        case none
        case move(startRect: CGRect, startPoint: CGPoint)
        case resize(handle: CaptureSelectionResizeHandle, startRect: CGRect)
        case create(startPoint: CGPoint)
    }

    private var selectionRect: CGRect {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    private let minSelectionSize: CGSize
    private var activePreset: CapturePreset
    private let hitSlop: CGFloat = 26
    private var dragOperation: DragOperation = .none
    private var trackingArea: NSTrackingArea?

    init(
        frame: CGRect,
        selectionRect: CGRect,
        minSelectionSize: CGSize,
        activePreset: CapturePreset
    ) {
        self.selectionRect = selectionRect.standardized
        self.minSelectionSize = minSelectionSize
        self.activePreset = activePreset
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if passesThroughSelectionBody,
           !wantsMouseEvents(at: point) {
            return nil
        }

        return super.hitTest(point)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    func setSelectionRect(_ selectionRect: CGRect) {
        self.selectionRect = selectionRect.standardized
    }

    func setActivePreset(_ preset: CapturePreset) {
        activePreset = preset
        window?.invalidateCursorRects(for: self)
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea

        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        let rect = selectionRect.standardized
        guard rect.width > 0, rect.height > 0 else { return }

        if activePreset.isFixedSize {
            addCursorRect(rect, cursor: .openHand)
            return
        }

        let slop = hitSlop
        let handleSize = slop * 2
        let horizontalEdgeWidth = max(0, rect.width - handleSize)
        let verticalEdgeHeight = max(0, rect.height - handleSize)

        addCursorRect(
            CGRect(x: rect.minX - slop, y: rect.maxY - slop, width: handleSize, height: handleSize),
            cursor: AllInOneResizeCursor.topLeft
        )
        addCursorRect(
            CGRect(x: rect.maxX - slop, y: rect.maxY - slop, width: handleSize, height: handleSize),
            cursor: AllInOneResizeCursor.topRight
        )
        addCursorRect(
            CGRect(x: rect.maxX - slop, y: rect.minY - slop, width: handleSize, height: handleSize),
            cursor: AllInOneResizeCursor.bottomRight
        )
        addCursorRect(
            CGRect(x: rect.minX - slop, y: rect.minY - slop, width: handleSize, height: handleSize),
            cursor: AllInOneResizeCursor.bottomLeft
        )

        if horizontalEdgeWidth > 0 {
            addCursorRect(
                CGRect(x: rect.minX + slop, y: rect.maxY - slop, width: horizontalEdgeWidth, height: handleSize),
                cursor: AllInOneResizeCursor.vertical
            )
            addCursorRect(
                CGRect(x: rect.minX + slop, y: rect.minY - slop, width: horizontalEdgeWidth, height: handleSize),
                cursor: AllInOneResizeCursor.vertical
            )
        }

        if verticalEdgeHeight > 0 {
            addCursorRect(
                CGRect(x: rect.minX - slop, y: rect.minY + slop, width: handleSize, height: verticalEdgeHeight),
                cursor: AllInOneResizeCursor.horizontal
            )
            addCursorRect(
                CGRect(x: rect.maxX - slop, y: rect.minY + slop, width: handleSize, height: verticalEdgeHeight),
                cursor: AllInOneResizeCursor.horizontal
            )
        }

        if !passesThroughSelectionBody {
            let bodyRect = rect.insetBy(dx: slop, dy: slop)
            if bodyRect.width > 0, bodyRect.height > 0 {
                addCursorRect(bodyRect, cursor: .openHand)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        let point = convert(event.locationInWindow, from: nil)
        if let fixedSize = activePreset.fixedPixelSize {
            if CaptureSelectionGeometry.hitTarget(
                at: point,
                selectionRect: selectionRect,
                hitSlop: hitSlop
            ) != nil {
                dragOperation = .move(startRect: selectionRect, startPoint: point)
                NSCursor.closedHand.set()
                return
            }

            let fixedRect = CaptureSelectionGeometry.fixedSize(
                CGSize(width: fixedSize.width, height: fixedSize.height),
                centeredAt: point,
                in: bounds
            )
            selectionRect = fixedRect
            dragOperation = .move(startRect: fixedRect, startPoint: point)
            onSelectionPreviewChanged?(selectionRect)
            NSCursor.closedHand.set()
            return
        }

        switch CaptureSelectionGeometry.hitTarget(
            at: point,
            selectionRect: selectionRect,
            hitSlop: hitSlop
        ) {
        case .resize(let handle):
            dragOperation = .resize(handle: handle, startRect: selectionRect)
            cursor(for: .resize(handle), at: point).set()
        case .move:
            dragOperation = .move(startRect: selectionRect, startPoint: point)
            NSCursor.closedHand.set()
        case nil:
            dragOperation = .create(startPoint: point)
            NSCursor.crosshair.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch dragOperation {
        case .none:
            return
        case let .move(startRect, startPoint):
            selectionRect = CaptureSelectionGeometry.move(
                startRect,
                by: CGVector(dx: point.x - startPoint.x, dy: point.y - startPoint.y),
                in: bounds
            )
        case let .resize(handle, startRect):
            if let ratio = activePreset.ratio, !activePreset.isFixedSize {
                selectionRect = CaptureSelectionGeometry.resize(
                    startRect,
                    handle: handle,
                    to: point,
                    in: bounds,
                    minSize: minSelectionSize,
                    aspectRatio: ratio
                )
            } else {
                selectionRect = CaptureSelectionGeometry.resize(
                    startRect,
                    handle: handle,
                    to: point,
                    in: bounds,
                    minSize: minSelectionSize
                )
            }
        case let .create(startPoint):
            if let ratio = activePreset.ratio, !activePreset.isFixedSize {
                selectionRect = CaptureSelectionGeometry.rect(
                    from: startPoint,
                    to: point,
                    in: bounds,
                    minSize: minSelectionSize,
                    aspectRatio: ratio
                )
            } else {
                selectionRect = CaptureSelectionGeometry.rect(
                    from: startPoint,
                    to: point,
                    in: bounds,
                    minSize: minSelectionSize
                )
            }
        }

        onSelectionPreviewChanged?(selectionRect)
    }

    override func mouseUp(with event: NSEvent) {
        guard case .none = dragOperation else {
            dragOperation = .none
            onSelectionChanged?(selectionRect)
            updateCursor(for: convert(event.locationInWindow, from: nil))
            return
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }

        onCancel?()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = selectionRect.standardized

        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.38).cgColor)
        context.fill(bounds)
        context.setBlendMode(.clear)
        context.fill(rect)
        context.restoreGState()

        drawSelectionChrome(in: context, rect: rect)
    }

    private func updateCursor(for point: CGPoint) {
        guard wantsMouseEvents(at: point) else { return }

        if activePreset.isFixedSize {
            if selectionRect.contains(point) {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
            return
        }

        cursor(
            for: CaptureSelectionGeometry.hitTarget(
                at: point,
                selectionRect: selectionRect,
                hitSlop: hitSlop
            ),
            at: point,
        ).set()
    }

    func wantsMouseEvents(at point: CGPoint) -> Bool {
        guard passesThroughSelectionBody else { return true }

        switch CaptureSelectionGeometry.hitTarget(
            at: point,
            selectionRect: selectionRect,
            hitSlop: hitSlop
        ) {
        case .resize:
            return true
        case .move:
            return false
        case nil:
            return true
        }
    }

    private func cursor(for target: CaptureSelectionHitTarget?, at point: CGPoint) -> NSCursor {
        switch target {
        case .move:
            return .openHand
        case .resize(.left), .resize(.right):
            return AllInOneResizeCursor.horizontal
        case .resize(.top), .resize(.bottom):
            return AllInOneResizeCursor.vertical
        case .resize(.topLeft):
            return AllInOneResizeCursor.topLeft
        case .resize(.topRight):
            return AllInOneResizeCursor.topRight
        case .resize(.bottomRight):
            return AllInOneResizeCursor.bottomRight
        case .resize(.bottomLeft):
            return AllInOneResizeCursor.bottomLeft
        case nil:
            return .arrow
        }
    }

    private func drawSelectionChrome(in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(1)
        context.stroke(rect)
        context.restoreGState()

        context.saveGState()
        context.setShadow(
            offset: .zero,
            blur: 7,
            color: NSColor.black.withAlphaComponent(0.55).cgColor
        )
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
        context.setLineWidth(3)
        context.setLineCap(.round)

        let cornerLength = min(24, max(8, min(rect.width, rect.height) / 3))
        let midLength = min(14, max(8, min(rect.width, rect.height) / 4))
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let midX = rect.midX
        let midY = rect.midY

        drawCorner(context, x: minX, y: maxY, dx: cornerLength, dy: -cornerLength)
        drawCorner(context, x: maxX, y: maxY, dx: -cornerLength, dy: -cornerLength)
        drawCorner(context, x: minX, y: minY, dx: cornerLength, dy: cornerLength)
        drawCorner(context, x: maxX, y: minY, dx: -cornerLength, dy: cornerLength)

        context.move(to: CGPoint(x: midX - midLength / 2, y: maxY))
        context.addLine(to: CGPoint(x: midX + midLength / 2, y: maxY))
        context.move(to: CGPoint(x: midX - midLength / 2, y: minY))
        context.addLine(to: CGPoint(x: midX + midLength / 2, y: minY))
        context.move(to: CGPoint(x: minX, y: midY - midLength / 2))
        context.addLine(to: CGPoint(x: minX, y: midY + midLength / 2))
        context.move(to: CGPoint(x: maxX, y: midY - midLength / 2))
        context.addLine(to: CGPoint(x: maxX, y: midY + midLength / 2))
        context.strokePath()
        context.restoreGState()
    }

    private func drawCorner(_ context: CGContext, x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat) {
        context.move(to: CGPoint(x: x, y: y))
        context.addLine(to: CGPoint(x: x + dx, y: y))
        context.move(to: CGPoint(x: x, y: y))
        context.addLine(to: CGPoint(x: x, y: y + dy))
        context.strokePath()
    }
}

@MainActor
private enum AllInOneResizeCursor {
    static let vertical = makeCursor(axis: CGVector(dx: 0, dy: 1))
    static let horizontal = makeCursor(axis: CGVector(dx: 1, dy: 0))
    static let topLeft = makeCursor(axis: CGVector(dx: -1, dy: 1))
    static let topRight = makeCursor(axis: CGVector(dx: 1, dy: 1))
    static let bottomRight = makeCursor(axis: CGVector(dx: 1, dy: -1))
    static let bottomLeft = makeCursor(axis: CGVector(dx: -1, dy: -1))

    private static func makeCursor(axis: CGVector) -> NSCursor {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        drawCursorTriangles(
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            axis: axis,
            color: NSColor.black.withAlphaComponent(0.70),
            lineWidth: 2.8
        )
        drawCursorTriangles(
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            axis: axis,
            color: .white,
            lineWidth: 1.25
        )

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: CGPoint(x: size.width / 2, y: size.height / 2))
    }

    private static func drawCursorTriangles(
        center: CGPoint,
        axis: CGVector,
        color: NSColor,
        lineWidth: CGFloat
    ) {
        let length = max(1, hypot(axis.dx, axis.dy))
        let ux = axis.dx / length
        let uy = axis.dy / length
        let px = -uy
        let py = ux
        let tipOffset: CGFloat = 6.2
        let baseOffset: CGFloat = 2.2
        let halfBase: CGFloat = 3.1
        let forward = CGPoint(x: center.x + ux * tipOffset, y: center.y + uy * tipOffset)
        let forwardBase = CGPoint(x: center.x + ux * baseOffset, y: center.y + uy * baseOffset)
        let backward = CGPoint(x: center.x - ux * tipOffset, y: center.y - uy * tipOffset)
        let backwardBase = CGPoint(x: center.x - ux * baseOffset, y: center.y - uy * baseOffset)

        color.setStroke()

        let path = NSBezierPath()
        path.lineJoinStyle = .round
        path.lineWidth = lineWidth

        path.move(to: forward)
        path.line(to: CGPoint(x: forwardBase.x + px * halfBase, y: forwardBase.y + py * halfBase))
        path.move(to: forward)
        path.line(to: CGPoint(x: forwardBase.x - px * halfBase, y: forwardBase.y - py * halfBase))
        path.move(to: backward)
        path.line(to: CGPoint(x: backwardBase.x + px * halfBase, y: backwardBase.y + py * halfBase))
        path.move(to: backward)
        path.line(to: CGPoint(x: backwardBase.x - px * halfBase, y: backwardBase.y - py * halfBase))
        path.stroke()
    }
}
