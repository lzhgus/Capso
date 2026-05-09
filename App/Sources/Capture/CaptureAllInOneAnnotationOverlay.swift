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
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let hostingView = AllInOneAnnotationToolbarHostingView(rootView: AllInOneAnnotationToolbarView(session: session))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = 14
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
        let usesCompact = session?.usesCompactToolbar ?? (globalRect.width < 760)
        let usesMini = session?.usesMiniToolbar ?? (globalRect.width < 420)
        let showsOverflow = session?.showsOverflow ?? false
        let width: CGFloat
        let height: CGFloat
        let maxToolbarWidth = screen.visibleFrame.width - margin * 2
        if usesCompact {
            if usesMini && !showsOverflow {
                width = min(268, maxToolbarWidth)
            } else if showsOverflow {
                width = min(760, maxToolbarWidth)
            } else {
                width = min(max(420, globalRect.width), min(760, maxToolbarWidth))
            }
            height = showsOverflow ? 102 : 54
        } else {
            width = min(max(760, globalRect.width), min(960, maxToolbarWidth))
            height = 58
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

private extension NSView {
    func firstSubview<T: NSView>(of type: T.Type) -> T? {
        if let view = self as? T {
            return view
        }
        for subview in subviews {
            if let match = subview.firstSubview(of: type) {
                return match
            }
        }
        return nil
    }
}

@MainActor
final class AllInOneAnnotationSession: ObservableObject {
    @Published var sourceImage: CGImage
    @Published var displayScale: CGFloat
    @Published var currentTool: AnnotationTool
    @Published var currentColor: AnnotationColor
    @Published var filled: Bool
    @Published var lineWidth: CGFloat
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
        self.lineWidth = Self.storedWidth(for: Self.storedTool())
        self.strokePattern = Self.storedStrokePattern()
        self.redactionMode = Self.storedRedactionMode()

        Task { [weak self] in
            guard let self else { return }
            if let regions = try? await TextRecognizer.recognize(
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
            pattern: strokePattern
        )
    }

    var effectiveTextFontSize: CGFloat {
        (currentTool == .text || isEditingText) ? lineWidth : Self.storedTextFontSize()
    }

    var usesCompactToolbar: Bool {
        availableWidth < 760
    }

    var usesMiniToolbar: Bool {
        availableWidth < 420
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
        persistWidth(lineWidth, for: currentTool)
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
            textFontSize: session.effectiveTextFontSize,
            zoomScale: session.displayScale,
            refreshTrigger: session.refreshTrigger,
            textRegions: session.textRegions,
            commitEditingTrigger: session.commitEditingTrigger,
            onDocumentChanged: { session.markChanged() },
            onSwitchToSelect: {
                session.document.clearSelection()
                session.switchTool(.select)
            },
            onTextEditingStarted: { fontSize in
                session.isEditingText = true
                if session.lineWidth != fontSize {
                    session.lineWidth = fontSize
                }
            },
            onTextEditingEnded: {
                session.isEditingText = false
                session.persistWidth(session.lineWidth, for: .text)
            }
        )
        .background(Color.clear)
    }
}

private struct AllInOneAnnotationToolbarView: View {
    @ObservedObject var session: AllInOneAnnotationSession

    private var isFontSizeMode: Bool {
        session.currentTool == .text || session.isEditingText
    }

    var body: some View {
        if session.usesMiniToolbar && !session.showsOverflow {
            miniToolbar
        } else {
            adaptiveToolbar
        }
    }

    private var adaptiveToolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                toolRow(primaryTools)

                divider

                if !session.usesCompactToolbar {
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

                    divider
                    primaryControls
                } else {
                    compactStatus
                }

                if session.usesCompactToolbar {
                    iconButton(
                        systemName: session.showsOverflow ? "chevron.up" : "ellipsis",
                        help: session.showsOverflow ? "Hide tools" : "More tools",
                        action: { session.toggleOverflow() }
                    )
                } else {
                    divider
                    undoRedoControls
                }
            }

            if session.usesCompactToolbar && session.showsOverflow {
                HStack(spacing: 10) {
                    toolRow(overflowTools)
                    divider
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
                    divider
                    primaryControls
                    divider
                    undoRedoControls
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(toolbarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.20, dampingFraction: 0.88), value: session.showsOverflow)
    }

    private var miniToolbar: some View {
        HStack(spacing: 9) {
            currentToolGlyph
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

            iconButton(
                systemName: "ellipsis",
                help: "More tools",
                action: { session.toggleOverflow() }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(toolbarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
    }

    private var toolbarBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.regularMaterial)
            .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
    }

    private var primaryTools: [AnnotationTool] {
        session.usesCompactToolbar
            ? [.select, .arrow, .line, .rectangle, .text, .freehand]
            : AnnotationTool.allCases
    }

    private var overflowTools: [AnnotationTool] {
        [.ellipse, .pixelate, .counter, .highlighter]
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
                Slider(value: Binding(
                    get: { session.lineWidth },
                    set: {
                        session.lineWidth = $0
                        session.persistWidth($0, for: session.currentTool)
                        session.updateSelectedStyle()
                    }
                ), in: sliderRange, step: sliderStep)
                .frame(width: 92)
                .help(sliderHelp)
            }

            if session.currentTool == .pixelate {
                redactionModeControl
            }

            if session.currentTool == .arrow || session.currentTool == .line {
                strokePatternControl
            }

            if session.currentTool != .counter
                && session.currentTool != .arrow
                && session.currentTool != .line
                && session.currentTool != .highlighter
                && session.currentTool != .pixelate
                && !isFontSizeMode {
                iconButton(
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

    private var undoRedoControls: some View {
        HStack(spacing: 4) {
            iconButton(
                systemName: "arrow.uturn.backward",
                help: "Undo",
                isEnabled: session.document.canUndo,
                action: {
                    session.document.undo()
                    session.markChanged()
                }
            )

            iconButton(
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
                toolButton(tool)
            }
        }
    }

    private var currentToolGlyph: some View {
        Group {
            if session.currentTool == .text {
                Text(verbatim: "Aa")
                    .font(.system(size: 13, weight: .semibold))
            } else {
                Image(systemName: iconName(for: session.currentTool))
                    .font(.system(size: 14, weight: .medium))
            }
        }
        .foregroundStyle(.white)
    }

    private var compactValueLabel: String {
        if session.currentTool == .pixelate {
            return "\(Int(session.lineWidth))px"
        }
        if isFontSizeMode {
            return "\(Int(session.lineWidth))pt"
        }
        return "\(Int(session.lineWidth))px"
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(width: 1, height: 30)
    }

    private var sliderRange: ClosedRange<CGFloat> {
        if isFontSizeMode { return 12...120 }
        switch session.currentTool {
        case .pixelate: return 4...48
        case .counter: return 12...40
        case .highlighter: return 10...100
        default: return 1...40
        }
    }

    private var sliderStep: CGFloat {
        switch session.currentTool {
        case .pixelate, .highlighter: return 2
        default: return 1
        }
    }

    private var sliderHelp: String {
        if isFontSizeMode { return "\(String(localized: "Font Size")): \(Int(session.lineWidth))" }
        switch session.currentTool {
        case .pixelate: return "\(String(localized: "Block Size")): \(Int(session.lineWidth))"
        case .counter: return "\(String(localized: "Counter Size")): \(Int(session.lineWidth))"
        case .highlighter: return "\(String(localized: "Highlighter Width")): \(Int(session.lineWidth))"
        default: return "\(String(localized: "Line Width")): \(Int(session.lineWidth))"
        }
    }

    private var redactionModeControl: some View {
        HStack(spacing: 2) {
            ForEach(RedactionMode.allCases, id: \.self) { mode in
                Button {
                    session.redactionMode = mode
                    UserDefaults.standard.set(mode.rawValue, forKey: "annotationRedactionMode")
                    session.updateSelectedStyle()
                } label: {
                    Text(mode.label)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 26)
                        .background(optionBackground(isActive: session.redactionMode == mode))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(Text(mode.label))
            }
        }
        .padding(2)
        .background(optionGroupBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("Redaction Mode")
    }

    private var strokePatternControl: some View {
        HStack(spacing: 2) {
            ForEach(StrokePattern.allCases, id: \.self) { pattern in
                Button {
                    session.strokePattern = pattern
                    UserDefaults.standard.set(pattern.rawValue, forKey: "annotationStrokePattern")
                    session.updateSelectedStyle()
                } label: {
                    StrokePatternGlyph(pattern: pattern)
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 26)
                        .background(optionBackground(isActive: session.strokePattern == pattern))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(Text(pattern.rawValue.capitalized))
            }
        }
        .padding(2)
        .background(optionGroupBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("Stroke Pattern")
    }

    private var optionGroupBackground: Color {
        Color.white.opacity(0.09)
    }

    private func optionBackground(isActive: Bool) -> Color {
        isActive ? Color.accentColor.opacity(0.48) : Color.white.opacity(0.001)
    }

    @ViewBuilder
    private func toolButton(_ tool: AnnotationTool) -> some View {
        Button(action: { session.switchTool(tool) }) {
            Group {
                if tool == .text {
                    Text(verbatim: "Aa")
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Image(systemName: iconName(for: tool))
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 29, height: 28)
            .background(session.currentTool == tool ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.001))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(helpText(for: tool))
    }

    private func iconButton(
        systemName: String,
        help: LocalizedStringKey,
        isActive: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 28)
                .background(buttonBackground(isActive: isActive, isEnabled: isEnabled))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .help(help)
    }

    private func buttonBackground(isActive: Bool, isEnabled: Bool) -> Color {
        if !isEnabled { return Color.white.opacity(0.06) }
        if isActive { return Color.accentColor.opacity(0.45) }
        return Color.white.opacity(0.10)
    }

    private func iconName(for tool: AnnotationTool) -> String {
        switch tool {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .freehand: return "pencil.tip"
        case .pixelate: return "eye.slash.fill"
        case .counter: return "number.circle.fill"
        case .highlighter: return "highlighter"
        }
    }

    private func helpText(for tool: AnnotationTool) -> LocalizedStringKey {
        switch tool {
        case .select: return "Select"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .freehand: return "Draw"
        case .pixelate: return "Pixelate / Blur"
        case .counter: return "Counter"
        case .highlighter: return "Highlighter"
        }
    }
}
