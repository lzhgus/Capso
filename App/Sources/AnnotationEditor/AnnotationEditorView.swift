// App/Sources/AnnotationEditor/AnnotationEditorView.swift
import SwiftUI
import AnnotationKit
import OCRKit
import SharedKit

struct AnnotationEditorView: View {
    let initialSourceImage: CGImage
    let document: AnnotationDocument
    let interactionState: AnnotationEditorInteractionState
    let onSave: (CGImage) -> Void
    let onCopy: (CGImage) -> Void
    let onPin: (CGImage) -> Void
    let onCancel: () -> Void

    /// The working image shown in the canvas. Starts equal to
    /// `initialSourceImage` and is swapped if a crop commit includes a
    /// rotate or flip. Annotations live in this image's coordinate space.
    @State private var sourceImage: CGImage

    init(
        sourceImage: CGImage,
        document: AnnotationDocument,
        interactionState: AnnotationEditorInteractionState,
        onSave: @escaping (CGImage) -> Void,
        onCopy: @escaping (CGImage) -> Void,
        onPin: @escaping (CGImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialSourceImage = sourceImage
        self.document = document
        self.interactionState = interactionState
        self.onSave = onSave
        self.onCopy = onCopy
        self.onPin = onPin
        self.onCancel = onCancel
        self._sourceImage = State(initialValue: sourceImage)
    }

    // MARK: - Persisted tool preferences (issue #75)
    // Tool / color / filled / per-tool sizes survive across editor sessions
    // via UserDefaults. `lineWidth` itself is session-local because its
    // meaning changes with the active tool; it is synced on every change into
    // the correct per-tool store below.
    @AppStorage("annotationLastTool") private var currentTool: AnnotationTool = .arrow
    @AppStorage("annotationLastColor") private var currentColor: AnnotationColor = .red
    @AppStorage("annotationFilled") private var filled: Bool = false
    @AppStorage("annotationShapeWidth") private var savedLineWidth: Double = 3
    @AppStorage("annotationBlockSize") private var savedBlockSize: Double = 12
    @AppStorage("annotationCounterSize") private var savedCounterSize: Double = 20
    @AppStorage("annotationHighlighterWidth") private var savedHighlighterWidth: Double = 20
    @AppStorage("annotationRedactionMode") private var redactionMode: RedactionMode = .pixelate
    @AppStorage("annotationStrokePattern") private var savedStrokePattern: StrokePattern = .solid
    @AppStorage("annotationTextFillEnabled") private var textFillEnabled: Bool = false
    @AppStorage("annotationTextOutlineEnabled") private var textOutlineEnabled: Bool = false
    @AppStorage("annotationTextStrokeEnabled") private var textStrokeEnabled: Bool = true
    /// Preserved font size for the Text tool. Swapped in/out of `lineWidth`
    /// as the user toggles tools — same pattern as savedBlockSize etc.
    @AppStorage("annotationTextFontSize") private var savedTextFontSize: Double = 48

    @State private var lineWidth: CGFloat = 3
    @State private var strokePattern: StrokePattern = .solid
    /// True while an inline text editor is active. Lets the toolbar show
    /// the font-size slider even when the tool is `.select` (happens when
    /// re-editing via double-click).
    @State private var isEditingText = false
    @State private var beautifySettings = BeautifySettings()
    @State private var showBeautifyPanel = false
    @State private var refreshTrigger = 0
    @State private var zoomScale: CGFloat = 1.0
    @State private var isCropMode = false
    @State private var outputSize: CGSize?
    @State private var commitEditingTrigger = 0
    /// Cached text line bounding boxes for smart highlighter snapping.
    @State private var textRegions: [CGRect] = []

    private var imageWidth: CGFloat { CGFloat(sourceImage.width) }
    private var imageHeight: CGFloat { CGFloat(sourceImage.height) }

    /// Visible image width after applying any committed crop. The canvas view
    /// is still rendered at full image size but clipped+offset to show only
    /// this region, so annotations stay in full-image coordinates while layout
    /// and Save output reflect the crop.
    private var effectiveImageWidth: CGFloat {
        document.cropRect?.width ?? imageWidth
    }

    private var effectiveImageHeight: CGFloat {
        document.cropRect?.height ?? imageHeight
    }

    private var cropOffsetX: CGFloat {
        -(document.cropRect?.minX ?? 0) * zoomScale
    }

    private var cropOffsetY: CGFloat {
        -(document.cropRect?.minY ?? 0) * zoomScale
    }

    private var previewContentWidth: CGFloat {
        beautifySettings.isEnabled ? effectiveImageWidth + beautifySettings.outerInset * 2 : effectiveImageWidth
    }

    private var previewContentHeight: CGFloat {
        beautifySettings.isEnabled ? effectiveImageHeight + beautifySettings.outerInset * 2 : effectiveImageHeight
    }

    private var previewOuterInset: CGFloat {
        beautifySettings.isEnabled ? beautifySettings.outerInset * zoomScale : 0
    }

    private var previewWidth: CGFloat {
        previewContentWidth * zoomScale
    }

    private var previewHeight: CGFloat {
        previewContentHeight * zoomScale
    }

    private var currentStyle: AnnotationKit.StrokeStyle {
        AnnotationKit.StrokeStyle(
            color: currentColor,
            lineWidth: lineWidth,
            opacity: currentTool == .highlighter ? 0.35 : 1.0,
            filled: filled,
            pattern: strokePattern
        )
    }

    /// Font size currently pushed to the canvas. When the slider is in
    /// font-size mode (text tool active OR mid-edit), the live slider value
    /// wins so dragging it updates the editor in real time. Otherwise we
    /// fall back to the preserved value from the last text session.
    private var effectiveTextFontSize: CGFloat {
        (currentTool == .text || isEditingText) ? lineWidth : CGFloat(savedTextFontSize)
    }

    private var textFillColor: AnnotationColor? {
        textFillEnabled ? .black : nil
    }

    private var textOutlineColor: AnnotationColor? {
        textOutlineEnabled ? .white : nil
    }

    private var textGlyphStrokeColor: AnnotationColor? {
        textStrokeEnabled ? .white : nil
    }

    /// Preserved width for the given tool. Bridges between the `Double`
    /// UserDefaults stores and the canvas's `CGFloat` slider value.
    private func savedWidth(for tool: AnnotationTool) -> CGFloat {
        switch tool {
        case .pixelate: return CGFloat(savedBlockSize)
        case .counter: return CGFloat(savedCounterSize)
        case .highlighter: return CGFloat(savedHighlighterWidth)
        case .text: return CGFloat(savedTextFontSize)
        default: return CGFloat(savedLineWidth)
        }
    }

    /// Persist the current slider value into the store that owns the given
    /// tool. Called on every slider change so a dragged-then-closed editor
    /// still saves the user's choice.
    private func persistWidth(_ width: CGFloat, for tool: AnnotationTool) {
        switch tool {
        case .pixelate: savedBlockSize = Double(width)
        case .counter: savedCounterSize = Double(width)
        case .highlighter: savedHighlighterWidth = Double(width)
        case .text: savedTextFontSize = Double(width)
        default: savedLineWidth = Double(width)
        }
    }

    /// Live preview of the Beautify background. For solid, just a filled Rect.
    /// For liquid glass, a blurred & saturation-boosted copy of the screenshot
    /// scaled to fill the background area — mirrors what `BeautifyRenderer`
    /// produces on export. Blur radius is scaled by `zoomScale` so that the
    /// perceived amount of blur matches the fixed 120-image-pixel blur used
    /// by the renderer at any zoom level.
    @ViewBuilder
    private var beautifyBackground: some View {
        switch beautifySettings.backgroundStyle {
        case .solid:
            Rectangle()
                .fill(beautifySettings.backgroundColor)
        case .liquidGlass:
            Image(decorative: sourceImage, scale: 1.0)
                .resizable()
                .scaledToFill()
                .saturation(1.9)
                .blur(radius: max(8, 120 * zoomScale), opaque: true)
                .overlay(Color.white.opacity(0.03))
                .clipped()
        }
    }

    var body: some View {
        if isCropMode {
            cropEditor
        } else {
            editorContent
        }
    }

    private var cropEditor: some View {
        CropEditorView(
            sourceImage: sourceImage,
            initialCropRect: document.cropRect,
            initialOutputSize: outputSize,
            canTransformImage: document.objects.isEmpty,
            onCancel: { isCropMode = false },
            onCommit: commitCrop
        )
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if showBeautifyPanel {
                BeautifyPanel(settings: $beautifySettings)
                Divider()
            }

            canvasArea
            zoomBar
        }
    }

    private var toolbar: some View {
        AnnotationToolbar(
            currentTool: $currentTool,
            currentColor: $currentColor,
            lineWidth: $lineWidth,
            strokePattern: $strokePattern,
            filled: $filled,
            textFillEnabled: $textFillEnabled,
            textOutlineEnabled: $textOutlineEnabled,
            textStrokeEnabled: $textStrokeEnabled,
            redactionMode: $redactionMode,
            showBeautifyPanel: $showBeautifyPanel,
            isEditingText: isEditingText,
            canUndo: document.canUndo,
            canRedo: document.canRedo,
            onUndo: { document.undo(); refreshTrigger += 1 },
            onRedo: { document.redo(); refreshTrigger += 1 },
            onSave: { save() },
            onCopy: { copy() },
            onPin: { pin() },
            onCancel: onCancel,
            onCrop: { isCropMode = true }
        )
    }

    private var canvasArea: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                previewCanvas
            }
            .background(Color(white: 0.12))
            .onAppear { handleCanvasAppear(size: geo.size) }
            .onChange(of: currentTool, handleToolChange)
            .onChange(of: currentColor) { _, _ in updateSelectedStyle() }
            .onChange(of: lineWidth, handleLineWidthChange)
            .onChange(of: strokePattern, handleStrokePatternChange)
            .onChange(of: filled) { _, _ in updateSelectedStyle() }
            .onChange(of: textFillEnabled) { _, _ in updateSelectedStyle() }
            .onChange(of: textOutlineEnabled) { _, _ in updateSelectedStyle() }
            .onChange(of: textStrokeEnabled) { _, _ in updateSelectedStyle() }
            .onChange(of: redactionMode) { _, _ in updateSelectedStyle() }
            .onChange(of: geo.size, handleCanvasSizeChange)
        }
    }

    private var previewCanvas: some View {
        ZStack {
            if beautifySettings.isEnabled {
                beautifyBackground
                    .frame(width: previewWidth, height: previewHeight)
            }

            annotationCanvas
        }
        .frame(
            width: beautifySettings.isEnabled ? previewWidth : effectiveImageWidth * zoomScale,
            height: beautifySettings.isEnabled ? previewHeight : effectiveImageHeight * zoomScale
        )
    }

    private var annotationCanvas: some View {
        AnnotationCanvasView(
            document: document,
            sourceImage: sourceImage,
            currentTool: currentTool,
            currentStyle: currentStyle,
            redactionMode: redactionMode,
            textFontSize: effectiveTextFontSize,
            textFillColor: textFillColor,
            textOutlineColor: textOutlineColor,
            textGlyphStrokeColor: textGlyphStrokeColor,
            zoomScale: zoomScale,
            refreshTrigger: refreshTrigger,
            textRegions: textRegions,
            commitEditingTrigger: commitEditingTrigger,
            onSwitchToSelect: switchToSelectTool,
            onInteractionChanged: handleCanvasInteractionChanged,
            onTextEditingStarted: handleTextEditingStarted,
            onTextEditingEnded: handleTextEditingEnded
        )
        .frame(width: imageWidth * zoomScale, height: imageHeight * zoomScale)
        .offset(x: cropOffsetX, y: cropOffsetY)
        .frame(
            width: effectiveImageWidth * zoomScale,
            height: effectiveImageHeight * zoomScale,
            alignment: .topLeading
        )
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: canvasCornerRadius))
        .shadow(color: canvasShadowColor, radius: canvasShadowRadius, y: canvasShadowOffsetY)
        .padding(previewOuterInset)
    }

    private var zoomBar: some View {
        HStack(spacing: 8) {
            Button(action: zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("-", modifiers: .command)

            Text("\(Int(zoomScale * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44)

            Button(action: zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("=", modifiers: .command)

            Button("Fit", action: refitToCurrentWindow)
                .buttonStyle(.borderless)
                .keyboardShortcut("0", modifiers: .command)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private var canvasCornerRadius: CGFloat {
        beautifySettings.isEnabled ? beautifySettings.clampedCornerRadius * zoomScale : 0
    }

    private var canvasShadowColor: Color {
        .black.opacity(beautifySettings.isEnabled && beautifySettings.shadowEnabled ? 0.25 : 0)
    }

    private var canvasShadowRadius: CGFloat {
        beautifySettings.clampedShadowRadius * zoomScale
    }

    private var canvasShadowOffsetY: CGFloat {
        beautifySettings.isEnabled && beautifySettings.shadowEnabled ? 6 * zoomScale : 0
    }

    private func commitCrop(newImage: CGImage?, newRect: CGRect?, newOutputSize: CGSize?) {
        if let newImage {
            sourceImage = newImage
            document.replaceImage(size: CGSize(width: newImage.width, height: newImage.height))
            document.setCropRect(newRect)
        } else {
            document.setCropRect(newRect)
        }
        outputSize = newOutputSize
        isCropMode = false
    }

    private func handleCanvasAppear(size: CGSize) {
        fitToWindow(availableSize: size)
        lineWidth = savedWidth(for: currentTool)
        strokePattern = savedStrokePattern
        Task {
            if let regions = try? await TextRecognizer.recognize(
                image: sourceImage, level: .fast, detectURLs: false
            ) {
                textRegions = regions.map(\.boundingBox)
            }
        }
    }

    private func handleToolChange(oldTool: AnnotationTool, newTool: AnnotationTool) {
        document.clearSelection()
        persistWidth(lineWidth, for: oldTool)
        lineWidth = savedWidth(for: newTool)
    }

    private func handleLineWidthChange(oldValue: CGFloat, newValue: CGFloat) {
        updateSelectedStyle()
        persistWidth(newValue, for: currentTool)
    }

    private func handleStrokePatternChange(oldValue: StrokePattern, newValue: StrokePattern) {
        savedStrokePattern = newValue
        updateSelectedStyle()
    }

    private func handleCanvasSizeChange(oldSize: CGSize, newSize: CGSize) {
        if zoomScale == fitScale(for: newSize) { return }
    }

    private func handleCanvasInteractionChanged(_ isInteracting: Bool) {
        interactionState.setCanvasInteraction(isInteracting)
    }

    private func switchToSelectTool() {
        document.clearSelection()
        currentTool = .select
    }

    private func handleTextEditingStarted(
        fontSize: CGFloat,
        hasFill: Bool,
        hasOutline: Bool,
        hasStroke: Bool
    ) {
        isEditingText = true
        interactionState.isEditingText = true
        textFillEnabled = hasFill
        textOutlineEnabled = hasOutline
        textStrokeEnabled = hasStroke
        if lineWidth != fontSize {
            lineWidth = fontSize
        }
    }

    private func handleTextEditingEnded() {
        isEditingText = false
        interactionState.isEditingText = false
        savedTextFontSize = Double(lineWidth)
    }

    private func refitToCurrentWindow() {
        if let window = NSApp.keyWindow {
            let toolbarH: CGFloat = 90
            let available = CGSize(
                width: window.contentView?.bounds.width ?? 800,
                height: (window.contentView?.bounds.height ?? 600) - toolbarH
            )
            fitToWindow(availableSize: available)
        }
    }

    private func fitScale(for size: CGSize) -> CGFloat {
        guard previewContentWidth > 0, previewContentHeight > 0 else { return 1 }
        let viewportPadding: CGFloat = 20
        let scaleX = (size.width - viewportPadding) / previewContentWidth
        let scaleY = (size.height - viewportPadding) / previewContentHeight
        return min(scaleX, scaleY, 1.0) // Never zoom above 100%
    }

    private func fitToWindow(availableSize: CGSize) {
        zoomScale = fitScale(for: availableSize)
    }

    private func zoomIn() {
        zoomScale = min(zoomScale * 1.25, 4.0)
    }

    private func zoomOut() {
        zoomScale = max(zoomScale / 1.25, 0.1)
    }

    /// Update the selected object's style when color/lineWidth/filled changes
    private func updateSelectedStyle() {
        if let obj = document.selectedObject {
            if let pixelate = obj as? PixelateObject {
                pixelate.blockSize = lineWidth
                pixelate.mode = redactionMode
                pixelate.style = currentStyle
            } else if let counter = obj as? CounterObject {
                counter.radius = lineWidth
                counter.style = AnnotationKit.StrokeStyle(color: currentColor, lineWidth: lineWidth, filled: filled)
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
        guard let annotated = AnnotationRenderer.render(
            sourceImage: sourceImage,
            objects: document.objects,
            cropRect: document.cropRect
        ) else {
            return nil
        }
        guard let rendered = BeautifyRenderer.render(image: annotated, settings: beautifySettings) else {
            return nil
        }
        guard let outputSize else { return rendered }

        let width = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))
        guard width != rendered.width || height != rendered.height else {
            return rendered
        }
        return ImageUtilities.resized(rendered, width: width, height: height) ?? rendered
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
        guard !interactionState.shouldSuppressCopyAction else {
            return
        }
        commitEditingTrigger += 1
        DispatchQueue.main.async {
            if let rendered = renderedOutputImage() {
                onCopy(rendered)
            }
        }
    }

    private func pin() {
        commitEditingTrigger += 1
        DispatchQueue.main.async {
            if let rendered = renderedOutputImage() {
                onPin(rendered)
            }
        }
    }
}
