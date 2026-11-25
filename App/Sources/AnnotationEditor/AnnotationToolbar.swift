// App/Sources/AnnotationEditor/AnnotationToolbar.swift
import AppKit
import SwiftUI
import AnnotationKit

struct AnnotationToolbar: View {
    @Binding var currentTool: AnnotationTool
    @Binding var currentColor: AnnotationColor
    @Binding var lineWidth: CGFloat
    @Binding var strokePattern: StrokePattern
    @Binding var arrowHead: ArrowHeadStyle
    @Binding var filled: Bool
    @Binding var textFillEnabled: Bool
    @Binding var textOutlineEnabled: Bool
    @Binding var textStrokeEnabled: Bool
    @Binding var redactionMode: RedactionMode
    @Binding var showBeautifyPanel: Bool
    /// True when an inline text edit is active (either via the text tool or
    /// by double-clicking an existing TextObject in select mode). When set,
    /// the size slider behaves as a Font Size control regardless of the
    /// currently selected tool — so users can keep tuning size while typing.
    var isEditingText: Bool = false
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onSave: () -> Void
    let onCopy: () -> Void
    let onPin: () -> Void
    let dragThumbnail: NSImage
    let onPrepareDrag: () -> Void
    let onDragFileURL: () -> URL?
    let onDragPreviewImage: () -> NSImage?
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void
    let isDragDisabled: Bool
    let onCancel: () -> Void
    let onCrop: () -> Void
    var presets: [AnnotationStylePreset] = []
    var onApplyPreset: (AnnotationStylePreset) -> Void = { _ in }
    var onSavePreset: () -> Void = {}
    var onRemovePreset: (AnnotationStylePreset) -> Void = { _ in }

    /// The size slider serves multiple tools: in text / editing mode it means
    /// font size; for other tools it retains its existing role.
    private var isFontSizeMode: Bool {
        currentTool == .text || isEditingText
    }

    var body: some View {
        HStack(spacing: 10) {
            // Only the editing tools scroll. The actions stay pinned so
            // Save/Copy/Close never slide out of reach on a display too
            // narrow for the toolbar's full width (issue #236).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    toolGroup
                    AnnotationToolbarDivider()
                    AnnotationColorControls(
                        currentColor: $currentColor,
                        swatchSize: 17,
                        selectedRingColor: .white
                    )
                    AnnotationToolbarDivider()
                    strokeGroup
                    AnnotationToolbarDivider()
                    editGroup
                    AnnotationToolbarDivider()
                    undoGroup
                }
            }
            Spacer(minLength: 0)
            actionGroup
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .annotationToolbarSurface()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onHover { hovering in
            if hovering {
                NSCursor.arrow.set()
            }
        }
        .onChange(of: currentTool) { _, _ in
            NSCursor.arrow.set()
        }
    }

    private var toolGroup: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                AnnotationToolbarToolButton(
                    tool: tool,
                    isActive: currentTool == tool,
                    action: { currentTool = tool }
                )
            }
        }
    }

    private var strokeGroup: some View {
        HStack(spacing: 7) {
            if isFontSizeMode || !(currentTool == .pixelate && redactionMode == .solid) {
                Slider(
                    value: $lineWidth,
                    in: AnnotationToolbarChrome.sizeRange(for: currentTool, isFontSizeMode: isFontSizeMode),
                    step: AnnotationToolbarChrome.sizeStep(for: currentTool, isFontSizeMode: isFontSizeMode)
                )
                .frame(width: 92)
                .help(AnnotationToolbarChrome.sizeHelp(
                    for: currentTool,
                    isFontSizeMode: isFontSizeMode,
                    value: lineWidth
                ))
            }

            if currentTool == .pixelate && !isFontSizeMode {
                AnnotationToolbarRedactionModeControl(selection: $redactionMode)
            }

            if currentTool == .arrow || currentTool == .line {
                AnnotationToolbarStrokePatternControl(selection: $strokePattern)
            }

            if currentTool == .arrow {
                AnnotationToolbarSegmentedControl(
                    options: ArrowHeadStyle.allCases,
                    selection: $arrowHead,
                    itemWidth: 34,
                    help: "Arrow Style",
                    itemHelp: { _ in Text("Arrow Style") }
                ) { style in
                    ArrowHeadGlyph(style: style)
                }
            }

            if isFontSizeMode {
                AnnotationToolbarTextEffects(
                    fill: $textFillEnabled,
                    outline: $textOutlineEnabled,
                    trace: $textStrokeEnabled
                )
            }

            if AnnotationToolbarChrome.showsFillToggle(for: currentTool, isFontSizeMode: isFontSizeMode) {
                AnnotationToolbarIconButton(
                    systemName: filled ? "square.fill" : "square",
                    help: "Fill Shape",
                    isActive: filled,
                    action: { filled.toggle() }
                )
            }
        }
    }

    private var editGroup: some View {
        HStack(spacing: 4) {
            presetsMenu

            AnnotationToolbarIconButton(
                systemName: "crop",
                help: "Crop",
                isEnabled: !isEditingText,
                action: onCrop
            )

            AnnotationToolbarIconButton(
                systemName: showBeautifyPanel ? "sparkles.rectangle.stack.fill" : "sparkles",
                help: "Beautify",
                isActive: showBeautifyPanel,
                action: { showBeautifyPanel.toggle() }
            )
        }
    }

    private var presetsMenu: some View {
        Menu {
            ForEach(presets) { preset in
                Button { onApplyPreset(preset) } label: {
                    Label { Text(preset.title) } icon: { Image(nsImage: preset.swatch) }
                        .labelStyle(.titleAndIcon)
                }
            }
            if !presets.isEmpty { Divider() }
            Button("Save Current Style", action: onSavePreset)
            if !presets.isEmpty {
                Menu("Remove") {
                    ForEach(presets) { preset in
                        Button(preset.title) { onRemovePreset(preset) }
                    }
                }
            }
        } label: {
            AnnotationToolbarIconFace(systemName: "bookmark", isEnabled: !isEditingText)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Style Presets")
        .disabled(isEditingText)
    }

    private var undoGroup: some View {
        HStack(spacing: 4) {
            AnnotationToolbarIconButton(
                systemName: "arrow.uturn.backward",
                help: "Undo",
                isEnabled: canUndo,
                action: onUndo
            )
            .keyboardShortcut("z", modifiers: .command)

            AnnotationToolbarIconButton(
                systemName: "arrow.uturn.forward",
                help: "Redo",
                isEnabled: canRedo,
                action: onRedo
            )
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }

    private var actionGroup: some View {
        HStack(spacing: 4) {
            AnnotationToolbarIconButton(systemName: "xmark", help: "Close", action: onCancel)

            dragActionButton

            copyActionButton

            AnnotationToolbarIconButton(systemName: "pin", help: "Pin", action: onPin)
                .keyboardShortcut("p", modifiers: .command)

            AnnotationToolbarIconButton(
                systemName: "square.and.arrow.down",
                help: "Save",
                isPrimary: true,
                action: onSave
            )
            .keyboardShortcut("s", modifiers: .command)
        }
    }

    private var dragActionButton: some View {
        ZStack {
            AnnotationToolbarIconFace(systemName: "hand.draw", isEnabled: !isDragDisabled)

            QuickAccessDragSourceView(
                thumbnail: dragThumbnail,
                dragImageSize: CGSize(width: 240, height: 160),
                fileURLProvider: onDragFileURL,
                dragImageProvider: onDragPreviewImage,
                onDragStarted: onDragStarted,
                onDragEnded: { _ in onDragEnded() }
            )
            .frame(width: 30, height: 28)
            .disabled(isDragDisabled)
            .accessibilityHidden(true)
        }
        .help(isDragDisabled ? "Finish text editing before dragging" : "Drag Edited Image")
        .onHover { hovering in
            if hovering && !isDragDisabled {
                onPrepareDrag()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drag Edited Image")
    }

    @ViewBuilder
    private var copyActionButton: some View {
        let button = AnnotationToolbarIconButton(
            systemName: "doc.on.doc",
            help: "Copy Image and Close (⌘C · ⏎ · ⌘⇧C)",
            action: onCopy
        )
        .keyboardShortcut("c", modifiers: [.command, .shift])
        if isEditingText {
            // Leave ⌘C and Return to the text field being edited.
            button
        } else {
            button.background {
                ZStack {
                    hiddenCopyShortcut(.return, modifiers: [])
                    // Plain ⌘C only reaches here when the canvas declined it,
                    // i.e. no annotation object is selected (issue #236/#237).
                    hiddenCopyShortcut(KeyEquivalent("c"), modifiers: .command)
                }
            }
        }
    }

    private func hiddenCopyShortcut(
        _ key: KeyEquivalent,
        modifiers: EventModifiers
    ) -> some View {
        Button(action: onCopy) { EmptyView() }
            .keyboardShortcut(key, modifiers: modifiers)
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }
}

extension AnnotationTool {
    var localizedShortcutHelpTitle: String {
        AnnotationToolShortcut.helpTitle(localizedToolName, for: self)
    }

    var localizedToolName: String {
        switch self {
        case .select: return String(localized: "Select")
        case .arrow: return String(localized: "Arrow")
        case .line: return String(localized: "Line")
        case .rectangle: return String(localized: "Rectangle")
        case .ellipse: return String(localized: "Ellipse")
        case .text: return String(localized: "Text")
        case .freehand: return String(localized: "Draw")
        case .pixelate: return String(localized: "Pixelate / Blur")
        case .counter: return String(localized: "Counter")
        case .highlighter: return String(localized: "Highlighter")
        case .spotlight: return String(localized: "Spotlight")
        }
    }
}

/// Segmented pickers on macOS only draw `Image` / `Text` labels, so glyphs are
/// rendered into template images (tinted for light and dark mode by the system).
private func templateGlyph(width: CGFloat, height: CGFloat, draw: @escaping (CGContext, CGSize) -> Void) -> Image {
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size, flipped: true) { _ in
        if let ctx = NSGraphicsContext.current?.cgContext { draw(ctx, size) }
        return true
    }
    image.isTemplate = true
    return Image(nsImage: image)
}

/// A small sample arrow drawn with the real renderer, so the picker matches the canvas.
struct ArrowHeadGlyph: View {
    let style: ArrowHeadStyle

    var body: some View {
        templateGlyph(width: 24, height: 14) { ctx, size in
            let arrow = ArrowObject(
                start: CGPoint(x: 3, y: size.height / 2),
                end: CGPoint(x: size.width - 3, y: size.height / 2),
                style: AnnotationKit.StrokeStyle(color: .black, lineWidth: 2, arrowHead: style)
            )
            arrow.headLength = 6
            arrow.render(in: ctx)
        }
    }
}

struct StrokePatternGlyph: View {
    let pattern: StrokePattern

    var body: some View {
        templateGlyph(width: 22, height: 14) { ctx, size in
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)
            switch pattern {
            case .solid:
                ctx.setLineWidth(2)
            case .dashed:
                ctx.setLineWidth(2)
                ctx.setLineDash(phase: 0, lengths: [7, 5])
            case .dotted:
                ctx.setLineWidth(2.4)
                ctx.setLineDash(phase: 0, lengths: [0, 5])
            }
            ctx.move(to: CGPoint(x: 3, y: size.height / 2))
            ctx.addLine(to: CGPoint(x: size.width - 3, y: size.height / 2))
            ctx.strokePath()
        }
    }
}
