import AppKit
import CaptureKit
import Observation
import SharedKit
import SwiftUI

@MainActor
final class CaptureAllInOneToolbarWindow {
    private static let minimumSelectionSize = CGSize(width: 24, height: 24)

    private var selectionOverlayWindow: NSPanel?
    private weak var selectionOverlayView: AllInOneSelectionOverlayView?
    private var toolbarWindow: NSPanel?
    private var globalEscMonitor: Any?
    private var localEscMonitor: Any?
    private var screenLocalSelectionRect: CGRect
    private let toolbarState: CaptureAllInOneToolbarState
    private let presets: [CapturePreset]
    private var activePreset: CapturePreset

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
    var onCancel: (() -> Void)?

    init(
        selectionRect: CGRect,
        screen: NSScreen,
        presets: [CapturePreset],
        activePreset: CapturePreset
    ) {
        let visiblePresets = presets.isEmpty ? [.freeform] : presets
        self.screenLocalSelectionRect = selectionRect.standardized
        self.presets = visiblePresets
        self.activePreset = activePreset
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
        installEscMonitor()
    }

    func close() {
        removeEscMonitor()
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
        panel.level = .screenSaver
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
        overlayView.onSelectionChanged = { [weak self] selectionRect in
            self?.updateSelection(selectionRect)
        }
        overlayView.onCancel = { [weak self] in
            self?.onCancel?()
        }
        panel.contentView = overlayView

        selectionOverlayView = overlayView
        selectionOverlayWindow = panel
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func showToolbar() {
        let panel = AllInOnePanel(
            contentRect: toolbarFrame(for: globalSelectionRect),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onEscape = { [weak self] in self?.onCancel?() }
        panel.level = .screenSaver + 1
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        panel.acceptsMouseMovedEvents = true
        panel.contentView = AllInOneToolbarHostingView(rootView: CaptureAllInOneToolbarView(
            state: toolbarState,
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
                self.onOCR?(self.screenLocalSelectionRect)
            },
            onRecording: { [weak self] in
                guard let self else { return }
                self.onRecording?(self.screenLocalSelectionRect)
            },
            onAnnotate: { [weak self] in
                guard let self else { return }
                self.onAnnotate?(self.screenLocalSelectionRect)
            },
            onCopy: { [weak self] in
                guard let self else { return }
                self.onCopy?(self.screenLocalSelectionRect)
            },
            onPresetSelected: { [weak self] preset in
                self?.applyPreset(preset)
            },
            onCancel: { [weak self] in self?.onCancel?() }
        ))

        toolbarWindow = panel
        panel.orderFrontRegardless()
    }

    private func toolbarFrame(for selectionRect: CGRect) -> CGRect {
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

    private func updateSelection(_ selectionRect: CGRect) {
        screenLocalSelectionRect = CaptureSelectionGeometry.move(
            selectionRect.standardized,
            by: .zero,
            in: screenLocalBounds
        )
        updateToolbarState()
        toolbarWindow?.setFrame(toolbarFrame(for: globalSelectionRect), display: true)
    }

    private func updateToolbarState() {
        toolbarState.width = max(1, Int(screenLocalSelectionRect.width.rounded()))
        toolbarState.height = max(1, Int(screenLocalSelectionRect.height.rounded()))
    }

    private func applyPreset(_ preset: CapturePreset) {
        activePreset = preset
        toolbarState.activePreset = preset
        selectionOverlayView?.setActivePreset(preset)

        let fittedRect = fittedSelectionRect(for: preset)
        screenLocalSelectionRect = fittedRect
        selectionOverlayView?.setSelectionRect(fittedRect)
        updateToolbarState()
        toolbarWindow?.setFrame(toolbarFrame(for: globalSelectionRect), display: true)
        onPresetChanged?(preset)
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

    private func installEscMonitor() {
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.onCancel?() }
        }
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.onCancel?()
            return nil
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

    init(selectionRect: CGRect, presets: [CapturePreset], activePreset: CapturePreset) {
        self.width = max(1, Int(selectionRect.width.rounded()))
        self.height = max(1, Int(selectionRect.height.rounded()))
        self.presets = presets
        self.activePreset = activePreset
    }
}

private struct CaptureAllInOneToolbarView: View {
    let state: CaptureAllInOneToolbarState
    let onArea: () -> Void
    let onFullscreen: () -> Void
    let onWindow: () -> Void
    let onScrolling: () -> Void
    let onTimer: () -> Void
    let onOCR: () -> Void
    let onRecording: () -> Void
    let onAnnotate: () -> Void
    let onCopy: () -> Void
    let onPresetSelected: (CapturePreset) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                modeButton(icon: "viewfinder", title: "Area", action: onArea)
                modeButton(icon: "display", title: "Fullscreen", action: onFullscreen)
                modeButton(icon: "macwindow", title: "Window", action: onWindow)
                modeButton(icon: "arrow.down.to.line.compact", title: "Scrolling", action: onScrolling)
                modeButton(icon: "timer", title: "Timer", action: onTimer)
                modeButton(textIcon: "Aa", title: "OCR", action: onOCR)
                modeButton(icon: "video", title: "Recording", action: onRecording)
            }

            divider

            HStack(spacing: 8) {
                dimensionPill
                presetMenu
                iconButton("pencil", help: "Annotate in place", action: onAnnotate)
                iconButton("doc.on.doc", help: "Copy selected area", action: onCopy)
                iconButton("xmark", help: "Cancel", action: onCancel)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.36), radius: 20, y: 8)
        .environment(\.colorScheme, .dark)
        .onHover { hovering in
            if hovering {
                NSCursor.arrow.set()
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(width: 1, height: 44)
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
            .background(Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .menuStyle(.borderlessButton)
        .help("Capture preset")
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
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .help("Selected area size")
    }

    private func modeButton(
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func iconButton(
        _ systemName: String,
        help: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private final class AllInOneSelectionOverlayView: NSView {
    var onSelectionChanged: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

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

        let bodyRect = rect.insetBy(dx: slop, dy: slop)
        if bodyRect.width > 0, bodyRect.height > 0 {
            addCursorRect(bodyRect, cursor: .openHand)
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
            onSelectionChanged?(selectionRect)
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

        onSelectionChanged?(selectionRect)
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
