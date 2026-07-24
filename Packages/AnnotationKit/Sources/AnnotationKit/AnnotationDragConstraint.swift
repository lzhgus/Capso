// Packages/AnnotationKit/Sources/AnnotationKit/AnnotationDragConstraint.swift
import CoreGraphics
import Foundation

/// How a Shift-held creation drag is constrained for a given tool.
public enum AnnotationDragConstraintKind: Sendable, Equatable {
    /// Box tools lock to 1:1 — a square rectangle, a circular ellipse.
    case square
    /// Line-like tools snap to 45° increments.
    case angle
    /// Shift has no effect (freehand strokes, text, counters).
    case none
}

/// Shift-drag constraints applied while creating annotation objects. Kept as
/// pure geometry so the live preview and the committed object can share it.
public enum AnnotationDragConstraint {
    public static func kind(for tool: AnnotationTool) -> AnnotationDragConstraintKind {
        switch tool {
        case .rectangle, .ellipse, .pixelate:
            return .square
        case .arrow, .line:
            return .angle
        case .select, .text, .freehand, .highlighter, .counter:
            return .none
        }
    }

    /// The drag endpoint to use for `tool` when Shift is held. Returns `end`
    /// unchanged for tools Shift does not constrain.
    public static func constrainedEnd(
        from start: CGPoint,
        to end: CGPoint,
        tool: AnnotationTool
    ) -> CGPoint {
        switch kind(for: tool) {
        case .square:
            return squaredEnd(from: start, to: end)
        case .angle:
            return angleSnappedEnd(from: start, to: end)
        case .none:
            return end
        }
    }

    /// Moves `end` so the box anchored at `start` is square, keeping the drag's
    /// direction on both axes. The axis with the larger delta sets the side
    /// length, matching the capture overlay's square lock.
    public static func squaredEnd(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let side = max(abs(dx), abs(dy))

        return CGPoint(
            x: start.x + (dx < 0 ? -side : side),
            y: start.y + (dy < 0 ? -side : side)
        )
    }

    /// Rotates `end` to the nearest 45° increment around `start`, preserving the
    /// drag length so the line keeps the size the pointer implies.
    public static func angleSnappedEnd(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return end }

        let increment = CGFloat.pi / 4
        let snappedAngle = (atan2(dy, dx) / increment).rounded() * increment

        return CGPoint(
            x: start.x + cos(snappedAngle) * length,
            y: start.y + sin(snappedAngle) * length
        )
    }
}
