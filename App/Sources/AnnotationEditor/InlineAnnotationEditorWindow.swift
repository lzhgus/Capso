import AppKit
import SwiftUI
import AnnotationKit
import CaptureKit
import OCRKit

@MainActor
final class InlineAnnotationEditorWindow: NSPanel {
    private let document: AnnotationDocument

    init(
        image: CGImage,
        screen: NSScreen,
        screenLocalRect: CGRect,
        onSave: @escaping (CGImage) -> Void,
        onCopy: @escaping (CGImage) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.document = AnnotationDocument(
            imageSize: CGSize(width: image.width, height: image.height)
        )

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
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.isMovable = false
        self.isRestorable = false
        self.setFrame(screen.frame, display: false)

        let view = InlineAnnotationEditorView(
            sourceImage: image,
            document: document,
            screenSize: screen.frame.size,
            screenLocalRect: screenLocalRect,
            onSave: { [weak self] rendered in
                onSave(rendered)
                self?.close()
            },
            onCopy: { [weak self] rendered in
                onCopy(rendered)
                self?.close()
            },
            onCancel: { [weak self] in
                onClose()
                self?.close()
            }
        )

        self.contentView = NSHostingView(rootView: view)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show() {
        orderFrontRegardless()
        makeKey()
    }
}

private struct InlineAnnotationEditorView: View {
    let sourceImage: CGImage
    let document: AnnotationDocument
    let screenSize: CGSize
    let screenLocalRect: CGRect
    let onSave: (CGImage) -> Void
    let onCopy: (CGImage) -> Void
    let onCancel: () -> Void

    @AppStorage("annotationLastTool") private var currentTool: AnnotationTool = .arrow
    @AppStorage("annotationLastColor") private var currentColor: AnnotationColor = .red
    @AppStorage("annotationFilled") private var filled: Bool = false
    @AppStorage("annotationShapeWidth") private var savedLineWidth: Double = 3
    @AppStorage("annotationBlockSize") private var savedBlockSize: Double = 12
    @AppStorage("annotationCounterSize") private var savedCounterSize: Double = 20
    @AppStorage("annotationHighlighterWidth") private var savedHighlighterWidth: Double = 20
    @AppStorage("annotationTextFontSize") private var savedTextFontSize: Double = 48

    @State private var lineWidth: CGFloat = 3
    @State private var isEditingText = false
    @State private var refreshTrigger = 0
    @State private var commitEditingTrigger = 0
    @State private var textRegions: [CGRect] = []

    private var imageSize: CGSize {
        CGSize(width: sourceImage.width, height: sourceImage.height)
    }

    private var displayScale: CGFloat {
        CaptureDisplayGeometry.displayScale(
            imageSize: imageSize,
            screenRect: screenLocalRect
        ) ?? 1
    }

    private var currentStyle: AnnotationKit.StrokeStyle {
        AnnotationKit.StrokeStyle(
            color: currentColor,
            lineWidth: lineWidth,
            opacity: currentTool == .highlighter ? 0.35 : 1.0,
            filled: filled
        )
    }

    private var effectiveTextFontSize: CGFloat {
        (currentTool == .text || isEditingText) ? lineWidth : CGFloat(savedTextFontSize)
    }

    private var canvasRect: CGRect {
        let width = imageSize.width * displayScale
        let height = imageSize.height * displayScale
        let screenTopY = screenSize.height - screenLocalRect.maxY
        return CGRect(
            x: screenLocalRect.midX - width / 2,
            y: screenTopY + (screenLocalRect.height - height) / 2,
            width: width,
            height: height
        )
    }

    private var toolbarRect: CGRect {
        let margin: CGFloat = 16
        let gap: CGFloat = 12
        let toolbarWidth = max(360, min(screenSize.width - margin * 2, 880))
        let toolbarHeight: CGFloat = 58
        let targetX = canvasRect.midX - toolbarWidth / 2
        let maxX = max(margin, screenSize.width - toolbarWidth - margin)
        let x = min(max(targetX, margin), maxX)

        let belowY = canvasRect.maxY + gap
        let y: CGFloat
        if belowY + toolbarHeight <= screenSize.height - margin {
            y = belowY
        } else {
            y = max(margin, canvasRect.minY - toolbarHeight - gap)
        }

        return CGRect(x: x, y: y, width: toolbarWidth, height: toolbarHeight)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            DimmingCutout(cutout: canvasRect.insetBy(dx: -1, dy: -1))
                .fill(Color.black.opacity(0.34), style: FillStyle(eoFill: true))

            AnnotationCanvasView(
                document: document,
                sourceImage: sourceImage,
                currentTool: currentTool,
                currentStyle: currentStyle,
                textFontSize: effectiveTextFontSize,
                zoomScale: displayScale,
                refreshTrigger: refreshTrigger,
                textRegions: textRegions,
                commitEditingTrigger: commitEditingTrigger,
                onSwitchToSelect: {
                    document.clearSelection()
                    currentTool = .select
                },
                onTextEditingStarted: { fontSize in
                    isEditingText = true
                    if lineWidth != fontSize {
                        lineWidth = fontSize
                    }
                },
                onTextEditingEnded: {
                    isEditingText = false
                    savedTextFontSize = Double(lineWidth)
                }
            )
            .frame(width: canvasRect.width, height: canvasRect.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.92), lineWidth: 1.5)
                    .shadow(color: .black.opacity(0.55), radius: 8)
            )
            .position(x: canvasRect.midX, y: canvasRect.midY)

            InlineAnnotationToolbar(
                currentTool: $currentTool,
                currentColor: $currentColor,
                lineWidth: $lineWidth,
                filled: $filled,
                isEditingText: isEditingText,
                canUndo: document.canUndo,
                canRedo: document.canRedo,
                onUndo: {
                    document.undo()
                    refreshTrigger += 1
                },
                onRedo: {
                    document.redo()
                    refreshTrigger += 1
                },
                onCancel: onCancel,
                onCopy: copy,
                onSave: save
            )
            .frame(width: toolbarRect.width, height: toolbarRect.height)
            .position(x: toolbarRect.midX, y: toolbarRect.midY)
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .background(Color.clear)
        .onAppear {
            lineWidth = savedWidth(for: currentTool)
            Task {
                if let regions = try? await TextRecognizer.recognize(
                    image: sourceImage,
                    level: .fast,
                    detectURLs: false
                ) {
                    textRegions = regions.map(\.boundingBox)
                }
            }
        }
        .onChange(of: currentTool) { oldTool, newTool in
            document.clearSelection()
            persistWidth(lineWidth, for: oldTool)
            lineWidth = savedWidth(for: newTool)
        }
        .onChange(of: currentColor) { _, _ in updateSelectedStyle() }
        .onChange(of: lineWidth) { _, newValue in
            updateSelectedStyle()
            persistWidth(newValue, for: currentTool)
        }
        .onChange(of: filled) { _, _ in updateSelectedStyle() }
    }

    private func savedWidth(for tool: AnnotationTool) -> CGFloat {
        switch tool {
        case .pixelate: return CGFloat(savedBlockSize)
        case .counter: return CGFloat(savedCounterSize)
        case .highlighter: return CGFloat(savedHighlighterWidth)
        case .text: return CGFloat(savedTextFontSize)
        default: return CGFloat(savedLineWidth)
        }
    }

    private func persistWidth(_ width: CGFloat, for tool: AnnotationTool) {
        switch tool {
        case .pixelate: savedBlockSize = Double(width)
        case .counter: savedCounterSize = Double(width)
        case .highlighter: savedHighlighterWidth = Double(width)
        case .text: savedTextFontSize = Double(width)
        default: savedLineWidth = Double(width)
        }
    }

    private func updateSelectedStyle() {
        if let obj = document.selectedObject {
            if let pixelate = obj as? PixelateObject {
                pixelate.blockSize = lineWidth
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
        AnnotationRenderer.render(sourceImage: sourceImage, objects: document.objects)
    }

    private func save() {
        commitEditingTrigger += 1
        DispatchQueue.main.async {
            if let rendered = renderedOutputImage() {
                onSave(rendered)
            }
        }
    }

    private func copy() {
        commitEditingTrigger += 1
        DispatchQueue.main.async {
            if let rendered = renderedOutputImage() {
                onCopy(rendered)
            }
        }
    }
}

private struct DimmingCutout: Shape {
    let cutout: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(in: cutout, cornerSize: CGSize(width: 6, height: 6))
        return path
    }
}

private struct InlineAnnotationToolbar: View {
    @Binding var currentTool: AnnotationTool
    @Binding var currentColor: AnnotationColor
    @Binding var lineWidth: CGFloat
    @Binding var filled: Bool

    let isEditingText: Bool
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCancel: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void

    private var isFontSizeMode: Bool {
        currentTool == .text || isEditingText
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                toolButton(.select)
                toolButton(.arrow)
                toolButton(.rectangle)
                toolButton(.ellipse)
                toolButton(.text)
                toolButton(.freehand)
                toolButton(.pixelate)
                toolButton(.counter)
                toolButton(.highlighter)
            }

            divider

            HStack(spacing: 3) {
                ForEach(AnnotationColor.allCases, id: \.self) { color in
                    Button(action: { currentColor = color }) {
                        Circle()
                            .fill(Color(cgColor: color.cgColor))
                            .frame(width: 17, height: 17)
                            .overlay(
                                Circle()
                                    .stroke(currentColor == color ? Color.white : Color.clear, lineWidth: 2)
                            )
                            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help(localizedColorName(for: color))
                }
            }

            divider

            HStack(spacing: 7) {
                Slider(value: $lineWidth, in: sliderRange, step: sliderStep)
                    .frame(width: 82)
                    .help(sliderHelp)

                if currentTool != .counter && currentTool != .highlighter && !isFontSizeMode {
                    iconButton(
                        systemName: filled ? "square.fill" : "square",
                        help: "Fill Shape",
                        isActive: filled,
                        action: { filled.toggle() }
                    )
                }
            }

            divider

            HStack(spacing: 4) {
                iconButton(
                    systemName: "arrow.uturn.backward",
                    help: "Undo",
                    isEnabled: canUndo,
                    action: onUndo
                )
                .keyboardShortcut("z", modifiers: .command)

                iconButton(
                    systemName: "arrow.uturn.forward",
                    help: "Redo",
                    isEnabled: canRedo,
                    action: onRedo
                )
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                iconButton(systemName: "xmark", help: "Close", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                iconButton(systemName: "doc.on.doc", help: "Copy", action: onCopy)
                    .keyboardShortcut("c", modifiers: .command)
                iconButton(systemName: "square.and.arrow.down", help: "Save", isPrimary: true, action: onSave)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
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
        switch currentTool {
        case .pixelate: return 4...48
        case .counter: return 12...40
        case .highlighter: return 10...100
        default: return 1...40
        }
    }

    private var sliderStep: CGFloat {
        switch currentTool {
        case .pixelate, .highlighter: return 2
        default: return 1
        }
    }

    private var sliderHelp: String {
        if isFontSizeMode { return "\(String(localized: "Font Size")): \(Int(lineWidth))" }
        switch currentTool {
        case .pixelate: return "\(String(localized: "Block Size")): \(Int(lineWidth))"
        case .counter: return "\(String(localized: "Counter Size")): \(Int(lineWidth))"
        case .highlighter: return "\(String(localized: "Highlighter Width")): \(Int(lineWidth))"
        default: return "\(String(localized: "Line Width")): \(Int(lineWidth))"
        }
    }

    @ViewBuilder
    private func toolButton(_ tool: AnnotationTool) -> some View {
        Button(action: { currentTool = tool }) {
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
            .background(currentTool == tool ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.001))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(helpText(for: tool))
    }

    private func iconButton(
        systemName: String,
        help: LocalizedStringKey,
        isActive: Bool = false,
        isPrimary: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 28)
                .background(buttonBackground(isActive: isActive, isPrimary: isPrimary, isEnabled: isEnabled))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .help(help)
    }

    private func buttonBackground(isActive: Bool, isPrimary: Bool, isEnabled: Bool) -> Color {
        if !isEnabled { return Color.white.opacity(0.06) }
        if isPrimary { return Color.accentColor.opacity(0.82) }
        if isActive { return Color.accentColor.opacity(0.45) }
        return Color.white.opacity(0.10)
    }

    private func iconName(for tool: AnnotationTool) -> String {
        switch tool {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
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
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .freehand: return "Draw"
        case .pixelate: return "Pixelate / Blur"
        case .counter: return "Counter"
        case .highlighter: return "Highlighter"
        }
    }

    private func localizedColorName(for color: AnnotationColor) -> String {
        switch color {
        case .red: return String(localized: "Red")
        case .orange: return String(localized: "Orange")
        case .yellow: return String(localized: "Yellow")
        case .green: return String(localized: "Green")
        case .blue: return String(localized: "Blue")
        case .purple: return String(localized: "Purple")
        case .white: return String(localized: "White")
        case .black: return String(localized: "Black")
        }
    }
}
