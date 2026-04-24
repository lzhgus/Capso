// App/Sources/AnnotationEditor/AnnotationEditorView.swift
import SwiftUI
import AnnotationKit
import OCRKit

struct AnnotationEditorView: View {
    let sourceImage: CGImage
    let document: AnnotationDocument
    let onSave: (CGImage) -> Void
    let onCopy: (CGImage) -> Void
    let onCancel: () -> Void

    @State private var currentTool: AnnotationTool = .arrow
    @State private var currentColor: AnnotationColor = .red
    @State private var lineWidth: CGFloat = 3
    @State private var filled: Bool = false
    @State private var savedLineWidth: CGFloat = 3
    @State private var savedBlockSize: CGFloat = 12
    @State private var savedCounterSize: CGFloat = 20
    @State private var savedHighlighterWidth: CGFloat = 20
    /// Preserved font size for the Text tool. Swapped in/out of `lineWidth`
    /// as the user toggles tools — same pattern as savedBlockSize etc.
    @State private var savedTextFontSize: CGFloat = 48
    /// True while an inline text editor is active. Lets the toolbar show
    /// the font-size slider even when the tool is `.select` (happens when
    /// re-editing via double-click).
    @State private var isEditingText = false
    @State private var beautifySettings = BeautifySettings()
    @State private var showBeautifyPanel = false
    @State private var refreshTrigger = 0
    @State private var zoomScale: CGFloat = 1.0
    /// Cached text line bounding boxes for smart highlighter snapping.
    @State private var textRegions: [CGRect] = []

    private var imageWidth: CGFloat { CGFloat(sourceImage.width) }
    private var imageHeight: CGFloat { CGFloat(sourceImage.height) }

    private var previewContentWidth: CGFloat {
        beautifySettings.isEnabled ? imageWidth + beautifySettings.outerInset * 2 : imageWidth
    }

    private var previewContentHeight: CGFloat {
        beautifySettings.isEnabled ? imageHeight + beautifySettings.outerInset * 2 : imageHeight
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
            filled: filled
        )
    }

    /// Font size currently pushed to the canvas. When the slider is in
    /// font-size mode (text tool active OR mid-edit), the live slider value
    /// wins so dragging it updates the editor in real time. Otherwise we
    /// fall back to the preserved value from the last text session.
    private var effectiveTextFontSize: CGFloat {
        (currentTool == .text || isEditingText) ? lineWidth : savedTextFontSize
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
        VStack(spacing: 0) {
            // Toolbar pinned at top
            AnnotationToolbar(
                currentTool: $currentTool,
                currentColor: $currentColor,
                lineWidth: $lineWidth,
                filled: $filled,
                showBeautifyPanel: $showBeautifyPanel,
                isEditingText: isEditingText,
                canUndo: document.canUndo,
                canRedo: document.canRedo,
                onUndo: { document.undo(); refreshTrigger += 1 },
                onRedo: { document.redo(); refreshTrigger += 1 },
                onSave: { save() },
                onCopy: { copy() },
                onCancel: onCancel
            )
            Divider()

            if showBeautifyPanel {
                BeautifyPanel(settings: $beautifySettings)
                Divider()
            }

            // Canvas area with fit-to-window zoom
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        if beautifySettings.isEnabled {
                            beautifyBackground
                                .frame(width: previewWidth, height: previewHeight)
                        }

                        AnnotationCanvasView(
                            document: document,
                            sourceImage: sourceImage,
                            currentTool: currentTool,
                            currentStyle: currentStyle,
                            textFontSize: effectiveTextFontSize,
                            zoomScale: zoomScale,
                            refreshTrigger: refreshTrigger,
                            textRegions: textRegions,
                            onSwitchToSelect: {
                                document.clearSelection()
                                currentTool = .select
                            },
                            onTextEditingStarted: { fontSize in
                                isEditingText = true
                                // Sync slider to the object's fontSize when
                                // re-editing. Harmless for fresh edits: the
                                // value matches what we just pushed in.
                                if lineWidth != fontSize {
                                    lineWidth = fontSize
                                }
                            },
                            onTextEditingEnded: {
                                isEditingText = false
                                // Preserve the last-used font size for the
                                // next text edit / tool switch.
                                savedTextFontSize = lineWidth
                            }
                        )
                        .frame(
                            width: imageWidth * zoomScale,
                            height: imageHeight * zoomScale
                        )
                        .clipShape(RoundedRectangle(cornerRadius: beautifySettings.isEnabled ? beautifySettings.clampedCornerRadius * zoomScale : 0))
                        .shadow(
                            color: .black.opacity(beautifySettings.isEnabled && beautifySettings.shadowEnabled ? 0.25 : 0),
                            radius: beautifySettings.clampedShadowRadius * zoomScale,
                            y: beautifySettings.isEnabled && beautifySettings.shadowEnabled ? 6 * zoomScale : 0
                        )
                        .padding(previewOuterInset)
                    }
                    .frame(
                        width: beautifySettings.isEnabled ? previewWidth : imageWidth * zoomScale,
                        height: beautifySettings.isEnabled ? previewHeight : imageHeight * zoomScale
                    )
                }
                .background(Color(white: 0.12))
                .onAppear {
                    fitToWindow(availableSize: geo.size)
                    // Pre-cache text regions for smart highlighter snapping
                    Task {
                        if let regions = try? await TextRecognizer.recognize(
                            image: sourceImage, level: .fast, detectURLs: false
                        ) {
                            textRegions = regions.map(\.boundingBox)
                        }
                    }
                }
                .onChange(of: currentTool) { oldTool, newTool in
                    // Clear selection so restoring lineWidth below doesn't
                    // overwrite the previously drawn object's style.
                    document.clearSelection()

                    // Save outgoing tool's value
                    switch oldTool {
                    case .pixelate: savedBlockSize = lineWidth
                    case .counter: savedCounterSize = lineWidth
                    case .highlighter: savedHighlighterWidth = lineWidth
                    case .text: savedTextFontSize = lineWidth
                    default: savedLineWidth = lineWidth
                    }
                    // Restore incoming tool's value
                    switch newTool {
                    case .pixelate: lineWidth = savedBlockSize
                    case .counter: lineWidth = savedCounterSize
                    case .highlighter: lineWidth = savedHighlighterWidth
                    case .text: lineWidth = savedTextFontSize
                    default: lineWidth = savedLineWidth
                    }
                }
                .onChange(of: currentColor) { _, _ in updateSelectedStyle() }
                .onChange(of: lineWidth) { _, _ in updateSelectedStyle() }
                .onChange(of: filled) { _, _ in updateSelectedStyle() }
                .onChange(of: geo.size) { _, newSize in
                    // Re-fit if window is resized and we're at fit scale
                    if zoomScale == fitScale(for: newSize) { return }
                }
            }

            // Bottom bar: zoom controls
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

                Button("Fit") {
                    // Re-calculate fit scale
                    if let window = NSApp.keyWindow {
                        let toolbarH: CGFloat = 90 // toolbar + zoom bar
                        let available = CGSize(
                            width: window.contentView?.bounds.width ?? 800,
                            height: (window.contentView?.bounds.height ?? 600) - toolbarH
                        )
                        fitToWindow(availableSize: available)
                    }
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("0", modifiers: .command)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.bar)
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
            } else if let counter = obj as? CounterObject {
                counter.radius = lineWidth
                counter.style = AnnotationKit.StrokeStyle(color: currentColor, lineWidth: lineWidth, filled: filled)
            } else {
                obj.style = currentStyle
            }
            refreshTrigger += 1
        }
    }

    private func renderedOutputImage() -> CGImage? {
        guard let annotated = AnnotationRenderer.render(sourceImage: sourceImage, objects: document.objects) else {
            return nil
        }
        return BeautifyRenderer.render(image: annotated, settings: beautifySettings)
    }

    private func save() {
        if let rendered = renderedOutputImage() {
            onSave(rendered)
        }
    }

    private func copy() {
        if let rendered = renderedOutputImage() {
            onCopy(rendered)
        }
    }
}
