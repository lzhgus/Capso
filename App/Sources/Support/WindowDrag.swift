// App/Sources/Support/WindowDrag.swift
import AppKit
import SwiftUI

/// Drags its window with the native window drag once the pointer moves; a press that never moves is a tap.
struct WindowDragHandle: NSViewRepresentable {
    var onTap: (() -> Void)?
    /// Receives the window's new origin in screen coordinates.
    var onDragEnded: ((NSPoint) -> Void)?

    final class HandleView: NSView {
        var onTap: (() -> Void)?
        var onDragEnded: ((NSPoint) -> Void)?
        private var mouseDownEvent: NSEvent?
        private var isDragging = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            isDragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard !isDragging, let mouseDownEvent else { return }
            let start = mouseDownEvent.locationInWindow
            let current = event.locationInWindow
            guard hypot(current.x - start.x, current.y - start.y) >= 4 else { return }
            isDragging = true
            window?.performDrag(with: mouseDownEvent)
        }

        override func mouseUp(with event: NSEvent) {
            defer {
                mouseDownEvent = nil
                isDragging = false
            }
            guard mouseDownEvent != nil, let window, window.isVisible else { return }
            if isDragging {
                onDragEnded?(window.frame.origin)
            } else {
                onTap?()
            }
        }
    }

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: HandleView, context: Context) {
        nsView.onTap = onTap
        nsView.onDragEnded = onDragEnded
    }
}

extension View {
    /// Lets the empty space of this view drag its window; controls on top keep their clicks.
    func dragsWindow() -> some View {
        background(WindowDragHandle())
    }
}
