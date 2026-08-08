import CoreGraphics

/// Pure layout math for the full-screen-independent Annotate window.
///
/// Capture images are pixel-backed (Retina screenshots are typically 2×), but
/// `NSWindow` frames are measured in points. Treating pixel dimensions as
/// points makes the window oversized — often larger than the visible display
/// — and AppKit then clamps it off-center (issue #236).
public enum AnnotationEditorWindowGeometry {
    /// Content-area size (points) for an image that must fit inside a fraction
    /// of the screen, leaving vertical room for toolbar / zoom chrome.
    public static func contentSize(
        imagePixelSize: CGSize,
        backingScaleFactor: CGFloat,
        visibleSize: CGSize,
        chromeHeight: CGFloat,
        maxViewportFraction: CGFloat = 0.8
    ) -> CGSize {
        guard imagePixelSize.width > 0,
              imagePixelSize.height > 0,
              visibleSize.width > 0,
              visibleSize.height > 0,
              maxViewportFraction > 0 else {
            return .zero
        }

        let scaleFactor = max(backingScaleFactor, 1)
        let pointWidth = imagePixelSize.width / scaleFactor
        let pointHeight = imagePixelSize.height / scaleFactor

        let maxWidth = visibleSize.width * maxViewportFraction
        let maxHeight = max(0, visibleSize.height * maxViewportFraction - max(chromeHeight, 0))
        guard maxWidth > 0, maxHeight > 0 else { return .zero }

        let fitScale = min(1, min(maxWidth / pointWidth, maxHeight / pointHeight))
        return CGSize(
            width: pointWidth * fitScale,
            height: pointHeight * fitScale + max(chromeHeight, 0)
        )
    }

    /// Centers a window frame of `size` inside `visibleFrame` (absolute desktop
    /// coordinates). Returns `.zero` when either input is empty.
    public static func centeredFrame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        guard size.width > 0,
              size.height > 0,
              visibleFrame.width > 0,
              visibleFrame.height > 0 else {
            return .zero
        }

        return CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
