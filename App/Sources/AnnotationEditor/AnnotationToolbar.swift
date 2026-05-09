// App/Sources/AnnotationEditor/AnnotationToolbar.swift
import SwiftUI
import AnnotationKit

struct AnnotationToolbar: View {
    @Binding var currentTool: AnnotationTool
    @Binding var currentColor: AnnotationColor
    @Binding var lineWidth: CGFloat
    @Binding var strokePattern: StrokePattern
    @Binding var filled: Bool
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
    let onCancel: () -> Void
    let onCrop: () -> Void

    /// The size slider serves multiple tools: in text / editing mode it means
    /// font size; for other tools it retains its existing role.
    private var isFontSizeMode: Bool {
        currentTool == .text || isEditingText
    }

    var body: some View {
        HStack(spacing: 12) {
            toolGroup
            toolbarDivider
            colorGroup
            toolbarDivider
            strokeGroup
            toolbarDivider
            cropGroup
            toolbarDivider
            beautifyGroup
            toolbarDivider
            undoGroup
            Spacer()
            actionGroup
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var toolGroup: some View {
        HStack(spacing: 4) {
            toolButton(.select, icon: "cursorarrow", label: "Select")
            toolButton(.arrow, icon: "arrow.up.right", label: "Arrow")
            toolButton(.line, icon: "line.diagonal", label: "Line")
            toolButton(.rectangle, icon: "rectangle", label: "Rectangle")
            toolButton(.ellipse, icon: "circle", label: "Ellipse")
            textToolButton
            toolButton(.freehand, icon: "pencil.tip", label: "Draw")
            toolButton(.pixelate, icon: "eye.slash.fill", label: "Pixelate / Blur")
            toolButton(.counter, icon: "number.circle.fill", label: "Counter")
            toolButton(.highlighter, icon: "highlighter", label: "Highlighter")
        }
    }

    private func toolButton(_ tool: AnnotationTool, icon: String, label: LocalizedStringKey) -> some View {
        Button(action: { currentTool = tool }) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(toolbarIconForeground(isActive: currentTool == tool))
                .frame(width: 30, height: 26)
                .background(toolbarButtonBackground(isActive: currentTool == tool))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(toolbarButtonStroke)
        }
        .buttonStyle(.plain)
        .help(label)
    }

    /// Text-tool button. Rendered as a literal "Aa" glyph rather than the
    /// SF Symbol `textformat`, because Apple localizes that symbol's
    /// appearance per language (en: "Aa", zh: "格式", ja: "書式", …) and
    /// we want a consistent look across all locales — the iconic "Aa"
    /// shorthand is the industry convention for a text tool.
    ///
    /// `Text(verbatim:)` prevents SwiftUI from treating "Aa" as a
    /// LocalizedStringKey lookup.
    private var textToolButton: some View {
        Button(action: { currentTool = .text }) {
            Text(verbatim: "Aa")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(toolbarIconForeground(isActive: currentTool == .text))
                .frame(width: 30, height: 26)
                .background(toolbarButtonBackground(isActive: currentTool == .text))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(toolbarButtonStroke)
        }
        .buttonStyle(.plain)
        .help("Text")
    }

    private var colorGroup: some View {
        AnnotationColorControls(currentColor: $currentColor)
    }

    private var strokeGroup: some View {
        HStack(spacing: 8) {
            if isFontSizeMode {
                // Text tool or mid-edit: slider becomes a font-size control.
                Slider(value: $lineWidth, in: 12...120, step: 1)
                    .frame(width: 80)
                    .help("Font Size: \(Int(lineWidth))")
            } else if currentTool == .pixelate {
                Picker("", selection: $redactionMode) {
                    ForEach(RedactionMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 184)
                .help("Redaction Mode")

                if redactionMode != .solid {
                    Slider(value: $lineWidth, in: 4...48, step: 2)
                        .frame(width: 80)
                        .help("Block Size: \(Int(lineWidth))")
                }
            } else if currentTool == .counter {
                Slider(value: $lineWidth, in: 12...40, step: 1)
                    .frame(width: 80)
                    .help("Counter Size: \(Int(lineWidth))")
            } else if currentTool == .highlighter {
                Slider(value: $lineWidth, in: 10...100, step: 2)
                    .frame(width: 80)
                    .help("Highlighter Width: \(Int(lineWidth))")
            } else {
                Slider(value: $lineWidth, in: 1...40, step: 1)
                    .frame(width: 80)
                    .help("Line Width: \(Int(lineWidth))")
            }
            if currentTool == .arrow || currentTool == .line {
                Picker("", selection: $strokePattern) {
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
            // Fill toggle is meaningless for counter / highlighter / text.
            if currentTool != .counter
                && currentTool != .arrow
                && currentTool != .line
                && currentTool != .highlighter
                && !isFontSizeMode {
                Toggle(isOn: $filled) {
                    Image(systemName: filled ? "square.fill" : "square")
                        .font(.system(size: 12))
                }
                .toggleStyle(.button)
                .help("Fill Shape")
            }
        }
    }

    private var cropGroup: some View {
        Button(action: onCrop) {
            Image(systemName: "crop")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(toolbarIconForeground(isActive: false))
                .frame(width: 30, height: 26)
                .background(toolbarButtonBackground(isActive: false))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(toolbarButtonStroke)
        }
        .buttonStyle(.plain)
        .help("Crop")
        .disabled(isEditingText)
    }

    private var beautifyGroup: some View {
        Button(action: { showBeautifyPanel.toggle() }) {
            Image(systemName: showBeautifyPanel ? "sparkles.rectangle.stack.fill" : "sparkles")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(toolbarIconForeground(isActive: showBeautifyPanel))
                .frame(width: 30, height: 26)
                .background(toolbarButtonBackground(isActive: showBeautifyPanel))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(toolbarButtonStroke)
        }
        .buttonStyle(.plain)
        .help("Beautify")
    }

    private var undoGroup: some View {
        HStack(spacing: 4) {
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo")
            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help("Redo")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var actionGroup: some View {
        HStack(spacing: 6) {
            actionButton(icon: "xmark", help: "Close", isDestructive: true, action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])

            actionButton(icon: "doc.on.doc", help: "Copy", action: onCopy)
                .keyboardShortcut("c", modifiers: .command)

            actionButton(icon: "pin", help: "Pin", action: onPin)
                .keyboardShortcut("p", modifiers: .command)

            actionButton(icon: "square.and.arrow.down", help: "Save", isPrimary: true, action: onSave)
                .keyboardShortcut("s", modifiers: .command)
        }
    }

    private func actionButton(
        icon: String,
        help: LocalizedStringKey,
        isPrimary: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(actionIconForeground(isPrimary: isPrimary, isDestructive: isDestructive))
                .frame(width: 34, height: 26)
                .background(actionButtonBackground(isPrimary: isPrimary, isDestructive: isDestructive))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(actionButtonStroke(isPrimary: isPrimary))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 24)
    }

    private func toolbarButtonBackground(isActive: Bool) -> Color {
        isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04)
    }

    private func toolbarIconForeground(isActive: Bool) -> Color {
        isActive ? Color.accentColor : Color.primary.opacity(0.82)
    }

    private var toolbarButtonStroke: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
    }

    private func actionButtonBackground(isPrimary: Bool, isDestructive: Bool) -> Color {
        if isPrimary {
            return Color.accentColor
        }
        if isDestructive {
            return Color.primary.opacity(0.045)
        }
        return Color.primary.opacity(0.055)
    }

    private func actionIconForeground(isPrimary: Bool, isDestructive: Bool) -> Color {
        if isPrimary {
            return .white
        }
        if isDestructive {
            return Color.primary.opacity(0.72)
        }
        return Color.primary.opacity(0.84)
    }

    private func actionButtonStroke(isPrimary: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(isPrimary ? Color.white.opacity(0.18) : Color.primary.opacity(0.08), lineWidth: 0.5)
    }
}

struct StrokePatternGlyph: View {
    let pattern: StrokePattern

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 3, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width - 3, y: size.height / 2))

            let style: SwiftUI.StrokeStyle
            switch pattern {
            case .solid:
                style = SwiftUI.StrokeStyle(lineWidth: 2, lineCap: .round)
            case .dashed:
                style = SwiftUI.StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 5])
            case .dotted:
                style = SwiftUI.StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [0, 5])
            }
            context.stroke(path, with: .color(.primary), style: style)
        }
        .frame(width: 22, height: 14)
    }
}
