import AppKit
import SwiftUI
import TranslationKit

@MainActor
final class TypedTranslationInputWindow: NSPanel {
    private var onCloseAction: (() -> Void)?

    init(
        onSubmit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onCloseAction = onClose

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let size = NSSize(width: 460, height: 300)
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = String(localized: "Translate Text")
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        contentView = NSHostingView(
            rootView: TypedTranslationInputView(
                onSubmit: onSubmit,
                onCancel: onCancel
            )
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    override func close() {
        onCloseAction?()
        onCloseAction = nil
        super.close()
    }
}

private struct TypedTranslationInputView: View {
    @State private var text = ""
    @FocusState private var textEditorFocused: Bool

    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    private var input: TypedTranslationInput {
        TypedTranslationInput(rawText: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.tint)
                Text("Translate Text")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Original")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($textEditorFocused)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                    )
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(action: submit) {
                    Label("Translate", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!input.canSubmit)
            }
        }
        .padding(20)
        .frame(width: 460, height: 300)
        .onAppear {
            textEditorFocused = true
        }
    }

    private func submit() {
        guard input.canSubmit else { return }
        onSubmit(text)
    }
}
