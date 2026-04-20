// Packages/EditorKit/Sources/EditorKit/ZoomInterpolator.swift

import CoreGraphics
import Foundation

/// Computes the zoom transform (scale + translation) at any timestamp based on
/// active zoom segments and cursor position.
public struct ZoomInterpolator: Sendable {

    // MARK: - Constants

    private static let zoomInDuration: TimeInterval = 0.8
    private static let zoomOutDuration: TimeInterval = 0.6
    private static let edgeSnapRatio: Double = 0.25

    // MARK: - Stored Properties

    /// Zoom segments sorted by startTime (ascending).
    private let segments: [ZoomSegment]
    private let frameWidth: Double
    private let frameHeight: Double

    // MARK: - Init

    public init(segments: [ZoomSegment], frameSize: CGSize) {
        self.segments = segments.sorted { $0.startTime < $1.startTime }
        self.frameWidth = frameSize.width
        self.frameHeight = frameSize.height
    }

    // MARK: - Public API

    /// Computes the `FrameTransform` at the given `time`.
    ///
    /// - Parameters:
    ///   - time: The playback timestamp in seconds.
    ///   - cursorPosition: Normalized cursor position (0–1 each axis).
    ///                     Used only when the segment's focus mode is `.followCursor`.
    /// - Returns: The appropriate `FrameTransform`, or `.identity` when no zoom is active.
    public func transform(
        at time: TimeInterval,
        cursorPosition: (x: Double, y: Double)?
    ) -> FrameTransform {
        guard let (segment, strength) = findActiveSegment(at: time), strength > 0 else {
            return .identity
        }

        // Determine raw focus point
        let rawFocus: (x: Double, y: Double)
        switch segment.focusMode {
        case .followCursor:
            rawFocus = cursorPosition ?? (x: 0.5, y: 0.5)
        case .manual(let x, let y):
            rawFocus = (x: x, y: y)
        }

        // Effective zoom level with transition strength applied
        let effectiveZoom = 1.0 + (segment.zoomLevel - 1.0) * strength

        // Apply edge snapping so the viewport never exceeds frame bounds
        let focus = edgeSnap(cursor: rawFocus, zoomLevel: effectiveZoom)

        // translateX/Y carry the normalized focus point (0-1) so the compositor
        // can build the correct scale-around-focus affine transform.
        return FrameTransform(scale: effectiveZoom, translateX: focus.x, translateY: focus.y)
    }

    // MARK: - Internal Helpers

    /// Returns the active segment and its current strength [0, 1] at `time`,
    /// or `nil` when no segment is active.
    func findActiveSegment(at time: TimeInterval) -> (segment: ZoomSegment, strength: Double)? {
        for segment in segments {
            let zoomInEnd = segment.startTime + Self.zoomInDuration
            let zoomOutStart = segment.endTime
            let zoomOutEnd = segment.endTime + Self.zoomOutDuration

            if time < segment.startTime {
                // Before this segment — segments are sorted, so no later one can match either…
                // Actually a later segment could still match, so just continue.
                continue
            }

            if time >= segment.startTime && time < zoomInEnd {
                // Zoom-in phase
                let progress = (time - segment.startTime) / Self.zoomInDuration
                let strength = easeOutCubic(t: progress)
                return (segment, strength)
            }

            if time >= zoomInEnd && time < zoomOutStart {
                // Hold phase (fully zoomed)
                return (segment, 1.0)
            }

            if time >= zoomOutStart && time < zoomOutEnd {
                // Zoom-out phase
                let progress = (time - zoomOutStart) / Self.zoomOutDuration
                let strength = 1.0 - easeOutCubic(t: progress)
                return (segment, strength)
            }

            // time >= zoomOutEnd — past this segment, keep iterating
        }
        return nil
    }

    /// Clamps a normalized focus coordinate so the zoomed viewport stays within
    /// the frame boundaries, using a linear snap near the edges.
    ///
    /// - Parameters:
    ///   - cursor: Normalized position (each axis in 0–1 range).
    ///   - zoomLevel: Effective scale factor (≥ 1).
    /// - Returns: Clamped/remapped focus point.
    func edgeSnap(cursor: (x: Double, y: Double), zoomLevel: Double) -> (x: Double, y: Double) {
        let snappedX = edgeSnapAxis(value: cursor.x, zoomLevel: zoomLevel)
        let snappedY = edgeSnapAxis(value: cursor.y, zoomLevel: zoomLevel)
        return (x: snappedX, y: snappedY)
    }

    // MARK: - Private Helpers

    private func edgeSnapAxis(value: Double, zoomLevel: Double) -> Double {
        let viewportHalf = 0.5 / zoomLevel
        let snapRatio = Self.edgeSnapRatio

        if value <= snapRatio {
            return viewportHalf
        } else if value >= 1.0 - snapRatio {
            return 1.0 - viewportHalf
        } else {
            // Linear remap from [snapRatio, 1-snapRatio] → [viewportHalf, 1-viewportHalf]
            let t = (value - snapRatio) / (1.0 - 2.0 * snapRatio)
            return viewportHalf + t * (1.0 - 2.0 * viewportHalf)
        }
    }

    /// Ease-out cubic: fast start, decelerates to target.
    /// `p = 1 - t; return 1 - p*p*p`
    private func easeOutCubic(t: Double) -> Double {
        let p = 1.0 - t
        return 1.0 - p * p * p
    }
}
