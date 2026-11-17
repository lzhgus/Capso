// App/Sources/Translation/WindowDrag.swift
import AppKit
import SwiftUI

private struct WindowDragHandle: NSViewRepresentable {
    final class HandleView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ nsView: HandleView, context: Context) {}
}

extension View {
    /// Lets the empty space of this view drag its window; controls on top keep their clicks.
    func dragsWindow() -> some View {
        background(WindowDragHandle())
    }
}
