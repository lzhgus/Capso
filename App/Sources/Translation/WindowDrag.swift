// App/Sources/Translation/WindowDrag.swift
import AppKit
import SwiftUI

/// Window dragging for the floating cards.
///
/// `isMovableByWindowBackground` only fires when the mouse-down lands on window
/// background that no view claims. Our cards are a single SwiftUI surface that
/// hit-tests end to end (`.background(.ultraThinMaterial)` over the whole
/// frame), so AppKit never sees that press and the window could not be moved at
/// all. The cards therefore drag themselves, the same way `SelfTimerHUD` and
/// `PinnedScreenshotWindow` already do.
enum WindowDragGeometry {
    /// SwiftUI's translation grows downward, an `NSWindow` origin grows upward.
    static func origin(start: NSPoint, translation: CGSize) -> NSPoint {
        NSPoint(x: start.x + translation.width, y: start.y - translation.height)
    }
}

private struct WindowDragModifier: ViewModifier {
    let window: () -> NSWindow?
    @State private var startOrigin: NSPoint?

    func body(content: Content) -> some View {
        content
            // A header made of buttons and spacers hit-tests only where it draws;
            // the shape makes the whole strip grabbable without swallowing taps.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        guard let window = window() else { return }
                        if startOrigin == nil {
                            startOrigin = window.frame.origin
                        }
                        guard let startOrigin else { return }
                        window.setFrameOrigin(
                            WindowDragGeometry.origin(start: startOrigin, translation: value.translation)
                        )
                    }
                    .onEnded { _ in
                        startOrigin = nil
                    }
            )
    }
}

extension View {
    /// Drags the window this surface belongs to. The `minimumDistance: 4` keeps
    /// plain clicks (and the buttons in the strip) working as taps.
    func dragsWindow(_ window: @escaping () -> NSWindow?) -> some View {
        modifier(WindowDragModifier(window: window))
    }
}
