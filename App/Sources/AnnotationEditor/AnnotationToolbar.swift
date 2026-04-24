// App/Sources/AnnotationEditor/AnnotationToolbar.swift
import SwiftUI
import AnnotationKit

struct AnnotationToolbar: View {
    @Binding var currentTool: AnnotationTool
    @Binding var currentColor: AnnotationColor
    @Binding var lineWidth: CGFloat
    @Binding var filled: Bool
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
    let onCancel: () -> Void

    /// The size slider serves multiple tools: in text / editing mode it means
    /// font size; for other tools it retains its existing role.
    private var isFontSizeMode: Bool {
        currentTool == .text || isEditingText
    }

    var body: some View {
        HStack(spacing: 12) {
            toolGroup
            Divider().frame(height: 24)
            colorGroup
            Divider().frame(height: 24)
            strokeGroup
            Divider().frame(height: 24)
            beautifyGroup
            Divider().frame(height: 24)
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
                .font(.system(size: 14))
                .frame(width: 30, height: 26)
                .background(currentTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
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
                .frame(width: 30, height: 26)
                .background(currentTool == .text ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Text")
    }

    private var colorGroup: some View {
        HStack(spacing: 3) {
            ForEach(AnnotationColor.allCases, id: \.self) { color in
                Button(action: { currentColor = color }) {
                    Circle()
                        .fill(Color(cgColor: color.cgColor))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(currentColor == color ? Color.white : Color.clear, lineWidth: 2))
                        .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help(Text(color.rawValue.capitalized))
            }
        }
    }

    private var strokeGroup: some View {
        HStack(spacing: 8) {
            if isFontSizeMode {
                // Text tool or mid-edit: slider becomes a font-size control.
                Slider(value: $lineWidth, in: 12...120, step: 1)
                    .frame(width: 80)
                    .help("Font Size: \(Int(lineWidth))")
            } else if currentTool == .pixelate {
                Slider(value: $lineWidth, in: 4...48, step: 2)
                    .frame(width: 80)
                    .help("Block Size: \(Int(lineWidth))")
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
            // Fill toggle is meaningless for counter / highlighter / text.
            if currentTool != .counter
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

    private var beautifyGroup: some View {
        Button(action: { showBeautifyPanel.toggle() }) {
            Image(systemName: showBeautifyPanel ? "sparkles.rectangle.stack.fill" : "sparkles")
                .font(.system(size: 14))
                .frame(width: 30, height: 26)
                .background(showBeautifyPanel ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
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
            Button(action: onCancel) {
                Label("Close", systemImage: "xmark")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.escape, modifiers: [])

            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("c", modifiers: .command)

            Button(action: onSave) {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut("s", modifiers: .command)
        }
    }
}
