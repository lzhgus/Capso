import CoreGraphics

/// Routes one scroll event to the behavior a zoomable canvas should apply.
///
/// Shared by the annotator's main scroll container and the inline overlay so the
/// two surfaces agree on what ⌘-scroll means. Command-scroll is treated as a
/// zoom gesture end to end: the events inside it that carry no usable scale
/// change (momentum, or a small / mostly-horizontal delta) resolve to `.ignore`
/// rather than falling through to a pan, which would shift the canvas in the
/// middle of a zoom.
public enum CanvasScrollGesture {
    public enum Action: Sendable, Equatable {
        /// Zoom by `factor`, anchored on the pointer.
        case zoom(factor: CGFloat)
        /// Pan the content by this delta, in `NSEvent.scrollingDelta`'s sign
        /// convention (positive y scrolls content down).
        case pan(dx: CGFloat, dy: CGFloat)
        /// Part of a ⌘-scroll gesture with no usable scale change. Callers must
        /// swallow it instead of panning.
        case ignore
    }

    public static func action(
        commandHeld: Bool,
        isMomentum: Bool,
        verticalDelta: CGFloat,
        horizontalDelta: CGFloat,
        hasPreciseDeltas: Bool
    ) -> Action {
        guard commandHeld else {
            return .pan(dx: horizontalDelta, dy: verticalDelta)
        }
        guard !isMomentum,
              let factor = ScrollZoomBehavior.scaleFactor(
                  verticalDelta: verticalDelta,
                  horizontalDelta: horizontalDelta,
                  hasPreciseDeltas: hasPreciseDeltas
              ) else {
            return .ignore
        }
        return .zoom(factor: factor)
    }
}
