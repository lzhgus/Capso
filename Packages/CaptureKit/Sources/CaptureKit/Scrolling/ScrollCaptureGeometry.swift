import CoreGraphics

/// Geometry helpers for scrolling capture selection and ScreenCaptureKit rects.
public enum ScrollCaptureGeometry {
    /// Clamps a screen-local, bottom-left selection into the screen-local
    /// `visibleFrame` so Dock / menu bar never enter the capture rect.
    public static func clampedScreenLocalSelection(
        selectionRect: CGRect,
        screenFrame: CGRect,
        visibleFrame: CGRect
    ) -> CGRect {
        let selection = selectionRect.standardized
        let screen = screenFrame.standardized
        let visible = visibleFrame.standardized

        guard selection.width > 0,
              selection.height > 0,
              screen.width > 0,
              screen.height > 0,
              visible.width > 0,
              visible.height > 0 else {
            return .null
        }

        let localVisible = CGRect(
            x: visible.minX - screen.minX,
            y: visible.minY - screen.minY,
            width: visible.width,
            height: visible.height
        )
        let intersection = selection.intersection(localVisible)
        return intersection.isNull || intersection.isEmpty ? .null : intersection
    }

    /// Converts a screen-local bottom-left rect into a top-left rect for
    /// ScreenCaptureKit's `sourceRect` (relative to the display origin).
    public static func topLeftCaptureRect(
        screenLocalSelection: CGRect,
        screenHeight: CGFloat
    ) -> CGRect {
        let selection = screenLocalSelection.standardized
        return CGRect(
            x: selection.origin.x,
            y: screenHeight - selection.origin.y - selection.height,
            width: selection.width,
            height: selection.height
        )
    }
}
