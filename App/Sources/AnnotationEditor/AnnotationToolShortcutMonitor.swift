import AppKit
import SwiftUI
import AnnotationKit

private struct AnnotationToolShortcutMonitor: NSViewRepresentable {
    @Binding var currentTool: AnnotationTool
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.currentTool = $currentTool
        context.coordinator.isEnabled = isEnabled
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.currentTool = $currentTool
        context.coordinator.isEnabled = isEnabled
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        var currentTool: Binding<AnnotationTool>?
        var isEnabled = true
        private var monitor: Any?

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isEnabled,
                  !isTextInputActive(in: event.window),
                  allowsToolShortcutModifiers(event.modifierFlags),
                  let key = event.charactersIgnoringModifiers,
                  let tool = AnnotationToolShortcut.tool(for: key) else {
                return event
            }

            currentTool?.wrappedValue = tool
            return nil
        }

        private func allowsToolShortcutModifiers(_ flags: NSEvent.ModifierFlags) -> Bool {
            let normalized = flags.intersection(.deviceIndependentFlagsMask)
            let disallowed: NSEvent.ModifierFlags = [.command, .option, .control, .function]
            return normalized.intersection(disallowed).isEmpty
        }

        private func isTextInputActive(in window: NSWindow?) -> Bool {
            guard let responder = window?.firstResponder else { return false }
            return responder is NSTextView
                || responder is NSTextField
                || responder is NSComboBox
        }
    }
}

extension View {
    func annotationToolShortcuts(
        currentTool: Binding<AnnotationTool>,
        isEnabled: Bool
    ) -> some View {
        background(
            AnnotationToolShortcutMonitor(
                currentTool: currentTool,
                isEnabled: isEnabled
            )
            .frame(width: 0, height: 0)
        )
    }
}
