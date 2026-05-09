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

    init(screen: NSScreen) {
        self.screen = screen
    }

    func show(sourceImage: CGImage, selectionRect: CGRect) {
        let session = AllInOneAnnotationSession(sourceImage: sourceImage)
        self.session = session

        showCanvas(session: session, selectionRect: selectionRect)
        showToolbar(session: session, selectionRect: selectionRect)
    }

    func update(sourceImage: CGImage, selectionRect: CGRect) {
        if let session, session.document.objects.isEmpty {
            session.replaceSourceImage(sourceImage)
        } else if session == nil {
            session = AllInOneAnnotationSession(sourceImage: sourceImage)
        }

        guard let session else { return }
        canvasWindow?.setFrame(canvasFrame(for: selectionRect), display: true)
        toolbarWindow?.setFrame(toolbarFrame(for: selectionRect), display: true)
        canvasWindow?.contentView = NSHostingView(rootView: AllInOneAnnotationCanvasView(
            session: session,
            displayScale: displayScale(for: sourceImage, selectionRect: selectionRect)
        ))
    }

    func close() {
        toolbarWindow?.close()
        toolbarWindow = nil
        canvasWindow?.close()
        canvasWindow = nil
        session = nil
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

        panel.contentView = NSHostingView(rootView: AllInOneAnnotationCanvasView(
            session: session,
            displayScale: displayScale(for: session.sourceImage, selectionRect: selectionRect)
        ))
        canvasWindow = panel
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func showToolbar(session: AllInOneAnnotationSession, selectionRect: CGRect) {
        let panel = AllInOneAnnotationPanel(
            contentRect: toolbarFrame(for: selectionRect),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver + 2
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        panel.contentView = NSHostingView(rootView: AllInOneAnnotationToolbarView(session: session))
        toolbarWindow = panel
        panel.orderFrontRegardless()
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

    private func toolbarFrame(for selectionRect: CGRect) -> CGRect {
        let margin: CGFloat = 12
        let gap: CGFloat = 10
        let width = min(max(760, selectionRect.width), screen.visibleFrame.width - margin * 2)
        let height: CGFloat = 58
        let globalRect = CGRect(
            x: screen.frame.minX + selectionRect.minX,
            y: screen.frame.minY + selectionRect.minY,
            width: selectionRect.width,
            height: selectionRect.height
        )

        let minX = screen.visibleFrame.minX + margin
        let maxX = screen.visibleFrame.maxX - width - margin
        let x = min(max(globalRect.midX - width / 2, minX), maxX)

        let belowY = globalRect.minY - height - gap
        let aboveY = globalRect.maxY + gap
        let y: CGFloat
        if belowY >= screen.visibleFrame.minY + margin {
            y = belowY
        } else if aboveY + height <= screen.visibleFrame.maxY - margin {
            y = aboveY
        } else {
            y = max(screen.visibleFrame.minY + margin, min(globalRect.minY + margin, screen.visibleFrame.maxY - height - margin))
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func displayScale(for image: CGImage, selectionRect: CGRect) -> CGFloat {
        CaptureDisplayGeometry.displayScale(
            imageSize: CGSize(width: image.width, height: image.height),
            screenRect: selectionRect
        ) ?? 1
    }
}

private final class AllInOneAnnotationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AllInOneAnnotationSession: ObservableObject {
    @Published var sourceImage: CGImage
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

    let document: AnnotationDocument

    private var savedLineWidth: Double {
        get { UserDefaults.standard.object(forKey: "annotationShapeWidth") as? Double ?? 3 }
        set { UserDefaults.standard.set(newValue, forKey: "annotationShapeWidth") }
    }

    init(sourceImage: CGImage) {
        self.sourceImage = sourceImage
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

    func replaceSourceImage(_ image: CGImage) {
        sourceImage = image
        document.replaceImage(size: CGSize(width: image.width, height: image.height))
        refreshTrigger += 1
    }

    func switchTool(_ newTool: AnnotationTool) {
        document.clearSelection()
        persistWidth(lineWidth, for: currentTool)
        currentTool = newTool
        lineWidth = Self.storedWidth(for: newTool)
        UserDefaults.standard.set(newTool.rawValue, forKey: "annotationLastTool")
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
    let displayScale: CGFloat

    var body: some View {
        AnnotationCanvasView(
            document: session.document,
            sourceImage: session.sourceImage,
            currentTool: session.currentTool,
            currentStyle: session.currentStyle,
            redactionMode: session.redactionMode,
            textFontSize: session.effectiveTextFontSize,
            zoomScale: displayScale,
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
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                toolButton(.select)
                toolButton(.arrow)
                toolButton(.line)
                toolButton(.rectangle)
                toolButton(.ellipse)
                toolButton(.text)
                toolButton(.freehand)
                toolButton(.pixelate)
                toolButton(.counter)
                toolButton(.highlighter)
            }

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
                    Picker("", selection: Binding(
                        get: { session.redactionMode },
                        set: {
                            session.redactionMode = $0
                            UserDefaults.standard.set($0.rawValue, forKey: "annotationRedactionMode")
                            session.updateSelectedStyle()
                        }
                    )) {
                        ForEach(RedactionMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 168)
                    .help("Redaction Mode")
                }

                if session.currentTool == .arrow || session.currentTool == .line {
                    Picker("", selection: Binding(
                        get: { session.strokePattern },
                        set: {
                            session.strokePattern = $0
                            UserDefaults.standard.set($0.rawValue, forKey: "annotationStrokePattern")
                            session.updateSelectedStyle()
                        }
                    )) {
                        ForEach(StrokePattern.allCases, id: \.self) { pattern in
                            StrokePatternGlyph(pattern: pattern)
                                .tag(pattern)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 104)
                    .help("Stroke Pattern")
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

            divider

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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
        .environment(\.colorScheme, .dark)
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
