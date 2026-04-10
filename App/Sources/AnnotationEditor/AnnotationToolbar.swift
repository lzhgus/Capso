// App/Sources/AnnotationEditor/AnnotationToolbar.swift
import SwiftUI
import AnnotationKit

struct AnnotationToolbar: View {
    @Binding var currentTool: AnnotationTool
    @Binding var currentColor: AnnotationColor
    @Binding var lineWidth: CGFloat
    @Binding var filled: Bool
    @Binding var showBeautifyPanel: Bool
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onSave: () -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void

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
            toolButton(.text, icon: "textformat", label: "Text")
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
            }
        }
    }

    private var strokeGroup: some View {
        HStack(spacing: 8) {
            if currentTool == .pixelate {
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
            if currentTool != .counter && currentTool != .highlighter {
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
            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var actionGroup: some View {
        HStack(spacing: 8) {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])
            Button("Copy", action: onCopy)
                .keyboardShortcut("c", modifiers: .command)
            Button("Save", action: onSave)
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
    }
}
