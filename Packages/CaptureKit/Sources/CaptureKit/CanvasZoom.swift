import CoreGraphics

/// Pure, layout-agnostic zoom math shared by the annotator's zoomable surfaces
/// (the main editor window and the inline overlay). Kept as a stateless enum of
/// static functions, mirroring `ScrollZoomBehavior`, so the geometry can be unit
/// tested in isolation from any AppKit/SwiftUI plumbing.
public enum CanvasZoom {
    /// Clamp a proposed scale (or zoom multiplier) into `[lower, upper]`.
    ///
    /// The main window clamps an absolute scale (e.g. `0.1...4.0`); the inline
    /// overlay clamps a `userZoom` multiplier layered on top of its fixed
    /// display scale (e.g. `1.0...8.0`).
    public static func clampScale(_ proposed: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(proposed, lower), upper)
    }

    /// Focal-point-preserving content offset, in the **content-origin**
    /// convention: `offset` is the content's top-left position (as fed to a
    /// SwiftUI `.offset`, where positive is down/right). Returns the new offset
    /// that keeps the content point under `focalPoint` visually fixed as the
    /// scale changes from `oldScale` to `newScale`.
    ///
    /// Derivation: with `r = newScale / oldScale`, the content point under the
    /// focus stays put when `newOffset = focalPoint * (1 - r) + currentOffset * r`.
    /// Both `focalPoint` and `currentOffset` must be expressed in the same
    /// coordinate frame; the formula is translation-covariant, so any consistent
    /// frame works.
    ///
    /// An `NSClipView.bounds.origin` is the negation of a content origin, so an
    /// AppKit caller negates on the way in and back out.
    public static func focalOffset(
        oldScale: CGFloat,
        newScale: CGFloat,
        focalPoint: CGPoint,
        currentOffset: CGPoint
    ) -> CGPoint {
        guard oldScale > 0 else { return currentOffset }
        let r = newScale / oldScale
        return CGPoint(
            x: focalPoint.x * (1 - r) + currentOffset.x * r,
            y: focalPoint.y * (1 - r) + currentOffset.y * r
        )
    }

    /// Constrain a content offset (content-origin convention, viewport-relative:
    /// `0` means the content's top-left sits at the viewport's top-left) so the
    /// scaled content keeps covering the viewport. When an axis of the content is
    /// smaller than the viewport it is centered on that axis.
    public static func clampOffset(
        _ offset: CGPoint,
        contentSize: CGSize,
        viewportSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: clampAxis(offset.x, content: contentSize.width, viewport: viewportSize.width),
            y: clampAxis(offset.y, content: contentSize.height, viewport: viewportSize.height)
        )
    }

    private static func clampAxis(_ value: CGFloat, content: CGFloat, viewport: CGFloat) -> CGFloat {
        if content <= viewport {
            // Content narrower than the viewport: center it.
            return (viewport - content) / 2
        }
        // Content larger than the viewport: valid origins run from
        // `viewport - content` (bottom/right edge flush) up to `0` (top/left flush).
        let lower = viewport - content
        return Swift.min(Swift.max(value, lower), 0)
    }
}
