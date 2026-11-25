import AppKit
import AnnotationKit
import CaptureKit
import OCRKit
import SwiftUI

@MainActor
final class CaptureAllInOneAnnotationOverlay {
    private let screen: NSScreen
    private var canvasWindow: NSPanel?
    private var toolbarWindow: NSPanel?
    private var session: AllInOneAnnotationSession?
    private var currentSelectionRect: CGRect?

    init(screen: NSScreen) {
        self.screen = screen
    }

    func show(sourceImage: CGImage, selectionRect: CGRect, avoidingFrame: CGRect?) {
        let session = AllInOneAnnotationSession(
            sourceImage: sourceImage,
            displayScale: displayScale(for: sourceImage, selectionRect: selectionRect)
        )
        session.onRequestCanvasFocus = { [weak self] in
            self?.focusCanvas()
        }
        session.onRequestToolbarLayout = { [weak self] in
            self?.repositionToolbar(selectionRect: selectionRect, avoidingFrame: avoidingFrame, animated: true)
        }
        session.availableWidth = selectionRect.width
        self.session = session
        currentSelectionRect = selectionRect

        showCanvas(session: session, selectionRect: selectionRect)
        showToolbar(session: session, selectionRect: selectionRect, avoidingFrame: avoidingFrame)
    }

    func update(sourceImage: CGImage, selectionRect: CGRect, avoidingFrame: CGRect?, isLive: Bool = false) {
        let previousSelectionRect = currentSelectionRect
        if session == nil {
            let newSession = AllInOneAnnotationSession(
                sourceImage: sourceImage,
                displayScale: displayScale(for: sourceImage, selectionRect: selectionRect)
            )
            newSession.onRequestCanvasFocus = { [weak self] in
                self?.focusCanvas()
            }
            newSession.onRequestToolbarLayout = { [weak self] in
                self?.repositionToolbar(selectionRect: selectionRect, avoidingFrame: avoidingFrame, animated: true)
            }
            session = newSession
        }

        guard let session else { return }
        let objectOffset = objectOffset(
            from: previousSelectionRect,
            to: selectionRect,
            sourceImage: session.sourceImage
        )
        session.replaceSourceImage(
            sourceImage,
            displayScale: displayScale(for: sourceImage, selectionRect: selectionRect),
            objectOffset: objectOffset
        )
        let wasCompact = session.usesCompactToolbar
        session.availableWidth = selectionRect.width
        if wasCompact != session.usesCompactToolbar {
            session.showsOverflow = false
        }
        session.onRequestToolbarLayout = { [weak self] in
            self?.repositionToolbar(selectionRect: selectionRect, avoidingFrame: avoidingFrame, animated: true)
        }
        canvasWindow?.setFrame(canvasFrame(for: selectionRect), display: true)
        toolbarWindow?.setFrame(toolbarFrame(for: selectionRect, avoidingFrame: avoidingFrame), display: !isLive)
        currentSelectionRect = selectionRect
    }

    func close() {
        toolbarWindow?.close()
        toolbarWindow = nil
        canvasWindow?.close()
        canvasWindow = nil
        session = nil
        currentSelectionRect = nil
    }

    func renderImage(afterCommit completion: @escaping (CGImage?) -> Void) {
        guard let session else {
            completion(nil)
            return
        }
        session.renderImage(afterCommit: completion)
    }

    var isEditingText: Bool {
        session?.isEditingText ?? false
    }

    func commitTextEditing() {
        session?.commitEditingTrigger += 1
    }

    var annotationDocument: AnnotationDocument? {
        session?.document
    }

    func performAnnotationClipboardShortcut(with event: NSEvent) -> Bool {
        canvasWindow?.contentView?.layoutSubtreeIfNeeded()
        return canvasWindow?.routeAnnotationClipboardShortcutToCanvas(event) ?? false
    }

    private func showCanvas(session: AllInOneAnnotationSession, selectionRect: CGRect) {
        let panel = AllInOneAnnotationPanel(
            contentRect: canvasFrame(for: selectionRect),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver + 1
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        panel.contentView = AllInOneCanvasHostingView(rootView: AllInOneAnnotationCanvasView(
            session: session
        ))
        canvasWindow = panel
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func showToolbar(session: AllInOneAnnotationSession, selectionRect: CGRect, avoidingFrame: CGRect?) {
        let panel = AllInOneAnnotationPanel(
            contentRect: toolbarFrame(for: selectionRect, avoidingFrame: avoidingFrame),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver + 3
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let hostingView = AllInOneAnnotationToolbarHostingView(rootView: AllInOneAnnotationToolbarView(session: session))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
        toolbarWindow = panel
        panel.orderFrontRegardless()
    }

    func repositionToolbar(selectionRect: CGRect, avoidingFrame: CGRect?, animated: Bool) {
        let frame = toolbarFrame(for: selectionRect, avoidingFrame: avoidingFrame)
        if animated {
            toolbarWindow?.setFrame(frame, display: true, animate: true)
        } else {
            toolbarWindow?.setFrame(frame, display: true)
        }
    }

    private func focusCanvas() {
        guard let canvasWindow else { return }
        canvasWindow.makeKey()
        if let canvas = canvasWindow.contentView?.firstSubview(of: AnnotationCanvasNSView.self) {
            canvasWindow.makeFirstResponder(canvas)
        }
    }

    private func canvasFrame(for selectionRect: CGRect) -> CGRect {
        let inset: CGFloat = 2
        let rect = selectionRect.insetBy(dx: inset, dy: inset)
        return CGRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.minY + rect.minY,
            width: max(1, rect.width),
            height: max(1, rect.height)
        )
    }

    private func toolbarFrame(for selectionRect: CGRect, avoidingFrame: CGRect?) -> CGRect {
        let margin: CGFloat = 12
        let gap: CGFloat = 10
        let globalRect = CGRect(
            x: screen.frame.minX + selectionRect.minX,
            y: screen.frame.minY + selectionRect.minY,
            width: selectionRect.width,
            height: selectionRect.height
        )
        let session = session
        let density = session?.toolbarDensity ?? CaptureChromeLayout.annotationDensity(for: globalRect.width)
        let usesCompact = density != .regular
        let usesMini = density == .mini
        let showsOverflow = session?.showsOverflow ?? false
        let height = CaptureChromeLayout.annotationToolbarHeight(
            density: density,
            showsOverflow: showsOverflow
        )
        let width: CGFloat
        let maxToolbarWidth = screen.visibleFrame.width - margin * 2
        if usesCompact {
            if usesMini && !showsOverflow {
                width = min(300, maxToolbarWidth)
            } else if showsOverflow {
                width = min(840, maxToolbarWidth)
            } else {
                width = min(max(480, globalRect.width), min(840, maxToolbarWidth))
            }
        } else {
            width = min(max(1_000, globalRect.width), min(1_000, maxToolbarWidth))
        }

        func clampedX(width: CGFloat) -> CGFloat {
            let minX = screen.visibleFrame.minX + margin
            let maxX = screen.visibleFrame.maxX - width - margin
            return min(max(globalRect.midX - width / 2, minX), maxX)
        }

        let belowY = globalRect.minY - height - gap
        let aboveY = globalRect.maxY + gap

        var candidates: [CGRect] = []
        if belowY >= screen.visibleFrame.minY + margin {
            candidates.append(CGRect(x: clampedX(width: width), y: belowY, width: width, height: height))
        }
        if aboveY + height <= screen.visibleFrame.maxY - margin {
            candidates.append(CGRect(x: clampedX(width: width), y: aboveY, width: width, height: height))
        }
        candidates.append(CGRect(
            x: clampedX(width: width),
            y: max(screen.visibleFrame.minY + margin, min(globalRect.minY + margin, screen.visibleFrame.maxY - height - margin)),
            width: width,
            height: height
        ))

        guard let avoidingFrame else {
            return candidates[0]
        }

        let inflatedAvoidance = avoidingFrame.insetBy(dx: -8, dy: -8)
        for candidate in candidates {
            let adjusted = toolbarFrame(candidate, avoiding: inflatedAvoidance, margin: margin, gap: gap)
            if !adjusted.intersects(inflatedAvoidance) {
                return adjusted
            }
        }

        return toolbarFrame(candidates[0], avoiding: inflatedAvoidance, margin: margin, gap: gap)
    }

    private func toolbarFrame(_ frame: CGRect, avoiding avoidance: CGRect, margin: CGFloat, gap: CGFloat) -> CGRect {
        guard frame.maxY > avoidance.minY && frame.minY < avoidance.maxY else {
            return frame
        }

        let visible = screen.visibleFrame
        let leftWidth = avoidance.minX - gap - (visible.minX + margin)
        let rightWidth = (visible.maxX - margin) - (avoidance.maxX + gap)

        if frame.midX <= avoidance.midX, leftWidth >= frame.width {
            return CGRect(x: avoidance.minX - gap - frame.width, y: frame.minY, width: frame.width, height: frame.height)
        }
        if rightWidth >= frame.width {
            return CGRect(x: avoidance.maxX + gap, y: frame.minY, width: frame.width, height: frame.height)
        }
        if leftWidth >= frame.width {
            return CGRect(x: avoidance.minX - gap - frame.width, y: frame.minY, width: frame.width, height: frame.height)
        }

        return frame
    }

    private func displayScale(for image: CGImage, selectionRect: CGRect) -> CGFloat {
        CaptureDisplayGeometry.displayScale(
            imageSize: CGSize(width: image.width, height: image.height),
            screenRect: selectionRect
        ) ?? 1
    }

    private func objectOffset(from oldRect: CGRect?, to newRect: CGRect, sourceImage: CGImage) -> CGSize {
        guard let oldRect else { return .zero }
        let scale = displayScale(for: sourceImage, selectionRect: oldRect)
        return CGSize(
            width: (oldRect.minX - newRect.minX) * scale,
            height: (newRect.maxY - oldRect.maxY) * scale
        )
    }
}

private final class AllInOneAnnotationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class AllInOneCanvasHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        if let canvas = firstSubview(of: AnnotationCanvasNSView.self) {
            window?.makeFirstResponder(canvas)
        }
        super.mouseDown(with: event)
    }
}

private final class AllInOneAnnotationToolbarHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        get { false }
        set { }
    }
}

@MainActor
final class AllInOneAnnotationSession: ObservableObject {
    @Published var sourceImage: CGImage
    @Published var displayScale: CGFloat
    @Published var currentTool: AnnotationTool
    @Published var currentColor: AnnotationColor
    @Published var filled: Bool
    @Published var textFillEnabled: Bool
    @Published var textOutlineEnabled: Bool
    @Published var textStrokeEnabled: Bool
    @Published var lineWidth: CGFloat
    @Published var textFontSize: CGFloat
    @Published var strokePattern: StrokePattern
    @Published var redactionMode: RedactionMode
    @Published var isEditingText = false
    @Published var refreshTrigger = 0
    @Published var commitEditingTrigger = 0
    @Published var textRegions: [CGRect] = []
    @Published var availableWidth: CGFloat = 0
    @Published var showsOverflow = false

    let document: AnnotationDocument
    var onRequestCanvasFocus: (() -> Void)?
    var onRequestToolbarLayout: (() -> Void)?

    private var savedLineWidth: Double {
        get { UserDefaults.standard.object(forKey: "annotationShapeWidth") as? Double ?? 3 }
        set { UserDefaults.standard.set(newValue, forKey: "annotationShapeWidth") }
    }

    init(sourceImage: CGImage, displayScale: CGFloat) {
        self.sourceImage = sourceImage
        self.displayScale = displayScale
        self.document = AnnotationDocument(imageSize: CGSize(width: sourceImage.width, height: sourceImage.height))
        self.currentTool = Self.storedTool()
        self.currentColor = Self.storedColor()
        self.filled = UserDefaults.standard.bool(forKey: "annotationFilled")
        self.textFillEnabled = UserDefaults.standard.bool(forKey: "annotationTextFillEnabled")
        self.textOutlineEnabled = UserDefaults.standard.bool(forKey: "annotationTextOutlineEnabled")
        self.textStrokeEnabled = Self.storedTextStrokeEnabled()
        self.lineWidth = Self.storedWidth(for: Self.storedTool())
        self.textFontSize = Self.storedTextFontSize()
        self.strokePattern = Self.storedStrokePattern()
        self.redactionMode = Self.storedRedactionMode()

        Task { [weak self] in
            guard let self else { return }
            if let regions = try? await OCRProcessFallback.recognize(
                image: sourceImage,
                level: .fast,
                detectURLs: false
            ) {
                self.textRegions = regions.map(\.boundingBox)
            }
        }
    }

    var currentStyle: AnnotationKit.StrokeStyle {
        AnnotationKit.StrokeStyle(
            color: currentColor,
            lineWidth: lineWidth,
            opacity: currentTool == .highlighter ? 0.35 : 1.0,
            filled: filled,
            pattern: strokePattern,
            arrowHead: ArrowHeadStyle(rawValue: UserDefaults.standard.string(forKey: "annotationArrowHead") ?? "") ?? .standard
        )
    }

    var isFontSizeMode: Bool {
        currentTool == .text || isEditingText
    }

    /// The toolbar slider edits the font size while text is in play, and the tool's width otherwise.
    var sliderValue: CGFloat {
        isFontSizeMode ? textFontSize : lineWidth
    }

    func setSliderValue(_ value: CGFloat) {
        if isFontSizeMode {
            textFontSize = value
            persistWidth(value, for: .text)
        } else {
            lineWidth = value
            persistWidth(value, for: currentTool)
            updateSelectedStyle()
        }
    }

    var textFillColor: AnnotationColor? {
        textFillEnabled ? .black : nil
    }

    var textOutlineColor: AnnotationColor? {
        textOutlineEnabled ? .white : nil
    }

    var textGlyphStrokeColor: AnnotationColor? {
        textStrokeEnabled ? .white : nil
    }

    var toolbarDensity: CaptureChromeDensity {
        CaptureChromeLayout.annotationDensity(for: availableWidth)
    }

    var usesCompactToolbar: Bool {
        toolbarDensity != .regular
    }

    var usesMiniToolbar: Bool {
        toolbarDensity == .mini
    }

    func replaceSourceImage(_ image: CGImage, displayScale: CGFloat, objectOffset: CGSize = .zero) {
        sourceImage = image
        self.displayScale = displayScale
        document.updateImageSizePreservingObjects(
            size: CGSize(width: image.width, height: image.height),
            objectOffset: objectOffset
        )
        refreshTrigger += 1
    }

    func switchTool(_ newTool: AnnotationTool) {
        document.clearSelection()
        if currentTool != .text {
            persistWidth(lineWidth, for: currentTool)
        }
        currentTool = newTool
        lineWidth = Self.storedWidth(for: newTool)
        UserDefaults.standard.set(newTool.rawValue, forKey: "annotationLastTool")
        onRequestCanvasFocus?()
    }

    func toggleOverflow() {
        guard usesCompactToolbar else { return }
        showsOverflow.toggle()
        onRequestToolbarLayout?()
    }

    func updateSelectedStyle() {
        if let obj = document.selectedObject {
            if let pixelate = obj as? PixelateObject {
                pixelate.blockSize = lineWidth
                pixelate.mode = redactionMode
                pixelate.style = currentStyle
            } else if let counter = obj as? CounterObject {
                counter.radius = lineWidth
                counter.style = AnnotationKit.StrokeStyle(
                    color: currentColor,
                    lineWidth: lineWidth,
                    filled: filled
                )
            } else if let text = obj as? TextObject {
                text.fillColor = textFillColor
                text.outlineColor = textOutlineColor
                text.glyphStrokeColor = textGlyphStrokeColor
                text.style = currentStyle
            } else {
                obj.style = currentStyle
            }
            refreshTrigger += 1
        }
    }

    private func renderedOutputImage() -> CGImage? {
        return AnnotationRenderer.render(sourceImage: sourceImage, objects: document.objects)
    }

    func renderImage(afterCommit completion: @escaping (CGImage?) -> Void) {
        commitEditingTrigger += 1
        DispatchQueue.main.async { [weak self] in
            completion(self?.renderedOutputImage())
        }
    }

    func markChanged() {
        refreshTrigger += 1
    }

    func persistWidth(_ width: CGFloat, for tool: AnnotationTool) {
        switch tool {
        case .pixelate:
            UserDefaults.standard.set(Double(width), forKey: "annotationBlockSize")
        case .counter:
            UserDefaults.standard.set(Double(width), forKey: "annotationCounterSize")
        case .highlighter:
            UserDefaults.standard.set(Double(width), forKey: "annotationHighlighterWidth")
        case .text:
            UserDefaults.standard.set(Double(width), forKey: "annotationTextFontSize")
        default:
            savedLineWidth = Double(width)
        }
    }

    private static func storedTool() -> AnnotationTool {
        if let raw = UserDefaults.standard.string(forKey: "annotationLastTool"),
           let tool = AnnotationTool(rawValue: raw) {
            return tool
        }
        return .arrow
    }

    private static func storedColor() -> AnnotationColor {
        if let raw = UserDefaults.standard.string(forKey: "annotationLastColor"),
           let color = AnnotationColor(rawValue: raw) {
            return color
        }
        return .red
    }

    private static func storedStrokePattern() -> StrokePattern {
        if let raw = UserDefaults.standard.string(forKey: "annotationStrokePattern"),
           let pattern = StrokePattern(rawValue: raw) {
            return pattern
        }
        return .solid
    }

    private static func storedRedactionMode() -> RedactionMode {
        let value = UserDefaults.standard.integer(forKey: "annotationRedactionMode")
        return RedactionMode(rawValue: value) ?? .pixelate
    }

    private static func storedTextStrokeEnabled() -> Bool {
        UserDefaults.standard.object(forKey: "annotationTextStrokeEnabled") as? Bool ?? true
    }

    private static func storedTextFontSize() -> CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: "annotationTextFontSize") as? Double ?? 48)
    }

    private static func storedWidth(for tool: AnnotationTool) -> CGFloat {
        switch tool {
        case .pixelate:
            return CGFloat(UserDefaults.standard.object(forKey: "annotationBlockSize") as? Double ?? 12)
        case .counter:
            return CGFloat(UserDefaults.standard.object(forKey: "annotationCounterSize") as? Double ?? 20)
        case .highlighter:
            return CGFloat(UserDefaults.standard.object(forKey: "annotationHighlighterWidth") as? Double ?? 20)
        case .text:
            return storedTextFontSize()
        default:
            return CGFloat(UserDefaults.standard.object(forKey: "annotationShapeWidth") as? Double ?? 3)
        }
    }
}

private struct AllInOneAnnotationCanvasView: View {
    @ObservedObject var session: AllInOneAnnotationSession

    var body: some View {
        AnnotationCanvasView(
            document: session.document,
            sourceImage: session.sourceImage,
            currentTool: session.currentTool,
            currentStyle: session.currentStyle,
            redactionMode: session.redactionMode,
            textFontSize: session.textFontSize,
            textFillColor: session.textFillColor,
            textOutlineColor: session.textOutlineColor,
            textGlyphStrokeColor: session.textGlyphStrokeColor,
            zoomScale: session.displayScale,
            refreshTrigger: session.refreshTrigger,
            textRegions: session.textRegions,
            commitEditingTrigger: session.commitEditingTrigger,
            onDocumentChanged: { session.markChanged() },
            onSwitchToSelect: {
                session.document.clearSelection()
                session.switchTool(.select)
            },
            onTextEditingStarted: { fontSize, hasFill, hasOutline, hasStroke in
                session.isEditingText = true
                session.textFillEnabled = hasFill
                session.textOutlineEnabled = hasOutline
                session.textStrokeEnabled = hasStroke
                if session.textFontSize != fontSize {
                    session.textFontSize = fontSize
                }
            },
            onTextEditingEnded: {
                session.isEditingText = false
                session.persistWidth(session.textFontSize, for: .text)
            }
        )
        .background(Color.clear)
    }
}

private struct AllInOneAnnotationToolbarView: View {
    @ObservedObject var session: AllInOneAnnotationSession
    @State private var showsTextStylePopover = false

    private var isFontSizeMode: Bool {
        session.isFontSizeMode
    }

    private var hasActiveTextEffect: Bool {
        session.textFillEnabled || session.textOutlineEnabled || session.textStrokeEnabled
    }

    var body: some View {
        Group {
            if session.usesMiniToolbar && !session.showsOverflow {
                miniToolbar
            } else {
                adaptiveToolbar
            }
        }
        .annotationToolShortcuts(
            currentTool: Binding(
                get: { session.currentTool },
                set: { session.switchTool($0) }
            ),
            isEnabled: !session.isEditingText
        )
        .onChange(of: isFontSizeMode) { _, isTextMode in
            if !isTextMode {
                showsTextStylePopover = false
            }
        }
    }

    private var adaptiveToolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                toolRow(primaryTools)

                AnnotationToolbarDivider()

                if !session.usesCompactToolbar {
                    colorControls
                    AnnotationToolbarDivider()
                    primaryControls
                } else {
                    compactStatus
                }

                if isFontSizeMode && session.usesCompactToolbar {
                    textStyleButton
                }

                if session.usesCompactToolbar {
                    AnnotationToolbarIconButton(
                        systemName: session.showsOverflow ? "chevron.up" : "ellipsis",
                        help: session.showsOverflow ? "Hide tools" : "More tools",
                        action: { session.toggleOverflow() }
                    )
                } else {
                    AnnotationToolbarDivider()
                    undoRedoControls
                }
            }

            if session.usesCompactToolbar && session.showsOverflow {
                HStack(spacing: 10) {
                    toolRow(overflowTools)
                    AnnotationToolbarDivider()
                    colorControls
                    AnnotationToolbarDivider()
                    primaryControls
                    AnnotationToolbarDivider()
                    undoRedoControls
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .annotationToolbarSurface()
        .animation(.spring(response: 0.20, dampingFraction: 0.88), value: session.showsOverflow)
    }

    private var miniToolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                AnnotationToolGlyph(tool: session.currentTool)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 28)
                    .background(Color.accentColor.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Circle()
                    .fill(Color(cgColor: session.currentColor.cgColor))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.white.opacity(0.62), lineWidth: 1.5))

                Text(compactValueLabel)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(minWidth: 34)

                if isFontSizeMode {
                    textStyleButton
                }

                AnnotationToolbarIconButton(
                    systemName: "ellipsis",
                    help: "More tools",
                    action: { session.toggleOverflow() }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .annotationToolbarSurface()
    }

    private var primaryTools: [AnnotationTool] {
        session.usesCompactToolbar
            ? [.select, .arrow, .line, .rectangle, .text, .freehand]
            : AnnotationTool.allCases
    }

    private var overflowTools: [AnnotationTool] {
        [.ellipse, .pixelate, .counter, .highlighter, .spotlight]
    }

    private var colorControls: some View {
        AnnotationColorControls(
            currentColor: Binding(
                get: { session.currentColor },
                set: {
                    session.currentColor = $0
                    UserDefaults.standard.set($0.rawValue, forKey: "annotationLastColor")
                    session.updateSelectedStyle()
                }
            ),
            swatchSize: 17,
            selectedRingColor: .white
        )
    }

    private var compactStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(cgColor: session.currentColor.cgColor))
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Color.white.opacity(0.62), lineWidth: 1.5))

            Text(compactValueLabel)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.86))
                .frame(minWidth: 36)
        }
    }

    private var primaryControls: some View {
        HStack(spacing: 7) {
            if !(session.currentTool == .pixelate && session.redactionMode == .solid) {
                Slider(
                    value: Binding(
                        get: { session.sliderValue },
                        set: { session.setSliderValue($0) }
                    ),
                    in: AnnotationToolbarChrome.sizeRange(for: session.currentTool, isFontSizeMode: isFontSizeMode),
                    step: AnnotationToolbarChrome.sizeStep(for: session.currentTool, isFontSizeMode: isFontSizeMode)
                )
                .frame(width: 92)
                .help(AnnotationToolbarChrome.sizeHelp(
                    for: session.currentTool,
                    isFontSizeMode: isFontSizeMode,
                    value: session.sliderValue
                ))
            }

            if session.currentTool == .pixelate {
                AnnotationToolbarRedactionModeControl(selection: Binding(
                    get: { session.redactionMode },
                    set: {
                        session.redactionMode = $0
                        UserDefaults.standard.set($0.rawValue, forKey: "annotationRedactionMode")
                        session.updateSelectedStyle()
                    }
                ))
            }

            if session.currentTool == .arrow || session.currentTool == .line {
                AnnotationToolbarStrokePatternControl(selection: Binding(
                    get: { session.strokePattern },
                    set: {
                        session.strokePattern = $0
                        UserDefaults.standard.set($0.rawValue, forKey: "annotationStrokePattern")
                        session.updateSelectedStyle()
                    }
                ))
            }

            if isFontSizeMode
                && CaptureChromeLayout.showsInlineTextEffects(for: session.toolbarDensity) {
                AnnotationToolbarTextEffects(
                    fill: Binding(
                        get: { session.textFillEnabled },
                        set: {
                            session.textFillEnabled = $0
                            UserDefaults.standard.set($0, forKey: "annotationTextFillEnabled")
                            session.updateSelectedStyle()
                        }
                    ),
                    outline: Binding(
                        get: { session.textOutlineEnabled },
                        set: {
                            session.textOutlineEnabled = $0
                            UserDefaults.standard.set($0, forKey: "annotationTextOutlineEnabled")
                            session.updateSelectedStyle()
                        }
                    ),
                    trace: Binding(
                        get: { session.textStrokeEnabled },
                        set: {
                            session.textStrokeEnabled = $0
                            UserDefaults.standard.set($0, forKey: "annotationTextStrokeEnabled")
                            session.updateSelectedStyle()
                        }
                    )
                )
            }

            if AnnotationToolbarChrome.showsFillToggle(for: session.currentTool, isFontSizeMode: isFontSizeMode) {
                AnnotationToolbarIconButton(
                    systemName: session.filled ? "square.fill" : "square",
                    help: "Fill Shape",
                    isActive: session.filled,
                    action: {
                        session.filled.toggle()
                        UserDefaults.standard.set(session.filled, forKey: "annotationFilled")
                        session.updateSelectedStyle()
                    }
                )
            }
        }
    }

    private var textStyleButton: some View {
        Button {
            showsTextStylePopover.toggle()
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(AnnotationToolbarChrome.buttonBackground(isActive: hasActiveTextEffect))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Text Style")
        .accessibilityLabel(Text("Text Style"))
        .accessibilityValue(Text(hasActiveTextEffect ? "On" : "Off"))
        .popover(isPresented: $showsTextStylePopover, arrowEdge: .top) {
            textStylePopover
        }
    }

    private var textStylePopover: some View {
        HStack(spacing: 6) {
            textStylePopoverButton(
                systemName: "rectangle.fill",
                label: "Background",
                isActive: session.textFillEnabled,
                defaultsKey: "annotationTextFillEnabled"
            ) {
                session.textFillEnabled.toggle()
                return session.textFillEnabled
            }
            textStylePopoverButton(
                systemName: "rectangle",
                label: "Box",
                isActive: session.textOutlineEnabled,
                defaultsKey: "annotationTextOutlineEnabled"
            ) {
                session.textOutlineEnabled.toggle()
                return session.textOutlineEnabled
            }
            textStylePopoverButton(
                systemName: "textformat",
                label: "Stroke",
                isActive: session.textStrokeEnabled,
                defaultsKey: "annotationTextStrokeEnabled"
            ) {
                session.textStrokeEnabled.toggle()
                return session.textStrokeEnabled
            }
        }
        .padding(10)
        .environment(\.colorScheme, .dark)
    }

    private func textStylePopoverButton(
        systemName: String,
        label: LocalizedStringKey,
        isActive: Bool,
        defaultsKey: String,
        toggle: @escaping () -> Bool
    ) -> some View {
        Button {
            let newValue = toggle()
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            session.updateSelectedStyle()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))

                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(width: 72, height: 48)
            .background(AnnotationToolbarChrome.buttonBackground(isActive: isActive))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityValue(Text(isActive ? "On" : "Off"))
    }

    private var undoRedoControls: some View {
        HStack(spacing: 4) {
            AnnotationToolbarIconButton(
                systemName: "arrow.uturn.backward",
                help: "Undo",
                isEnabled: session.document.canUndo,
                action: {
                    session.document.undo()
                    session.markChanged()
                }
            )

            AnnotationToolbarIconButton(
                systemName: "arrow.uturn.forward",
                help: "Redo",
                isEnabled: session.document.canRedo,
                action: {
                    session.document.redo()
                    session.markChanged()
                }
            )
        }
    }

    private func toolRow(_ tools: [AnnotationTool]) -> some View {
        HStack(spacing: 4) {
            ForEach(tools, id: \.self) { tool in
                AnnotationToolbarToolButton(
                    tool: tool,
                    isActive: session.currentTool == tool,
                    action: { session.switchTool(tool) }
                )
            }
        }
    }

    private var compactValueLabel: String {
        if isFontSizeMode && session.currentTool != .pixelate {
            return "\(Int(session.textFontSize))pt"
        }
        return "\(Int(session.lineWidth))px"
    }
}
