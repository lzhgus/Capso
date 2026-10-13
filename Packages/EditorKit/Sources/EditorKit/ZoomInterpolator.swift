// Packages/EditorKit/Sources/EditorKit/ZoomInterpolator.swift

import CoreGraphics
import Foundation

/// Computes the zoom transform (scale + translation) at any timestamp based on
/// active zoom segments and cursor position.
public struct ZoomInterpolator: Sendable {

    // MARK: - Constants

    /// Upper bound for each zoom-in / zoom-out ramp; short segments use half their length.
    static let rampDuration: TimeInterval = 0.75
    /// A segment starting within this long after the previous one ends is treated as back-to-back.
    private static let adjacencyTolerance: TimeInterval = 0.05
    private static let edgeSnapRatio: Double = 0.25
    /// No zoom, focused on the centre — the state ramps start from and return to.
    private static let unzoomed = FrameTransform(scale: 1, translateX: 0.5, translateY: 0.5)

    // MARK: - Stored Properties

    /// Zoom segments sorted by startTime (ascending).
    private let segments: [ZoomSegment]
    /// Camera paths for follow-cursor segments, aligned with `segments`.
    private let followPaths: [CursorFollowPath?]
    private let frameWidth: Double
    private let frameHeight: Double

    // MARK: - Init

    /// - Parameter cursorTimeline: When given, follow-cursor segments hold on
    ///   places where the cursor settles instead of chasing it every frame.
    public init(segments: [ZoomSegment], frameSize: CGSize, cursorTimeline: SmoothedCursorTimeline? = nil) {
        let resolved = Self.resolvingOverlaps(segments)
        self.segments = resolved
        self.followPaths = resolved.map { segment in
            guard case .followCursor = segment.focusMode, let cursorTimeline else { return nil }
            return CursorFollowPath(timeline: cursorTimeline, from: segment.startTime, to: segment.endTime)
        }
        self.frameWidth = frameSize.width
        self.frameHeight = frameSize.height
    }

    // MARK: - Public API

    /// Computes the `FrameTransform` at the given `time`.
    ///
    /// Both ramps happen inside the segment. Back-to-back segments move
    /// straight from one zoom to the next without returning to 1×, and a
    /// segment starting at the very beginning starts fully zoomed.
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
        guard let index = segments.indices.last(where: {
            segments[$0].startTime <= time && time < effectiveEnd(ofSegmentAt: $0)
        }) else {
            return .identity
        }
        let segment = segments[index]
        let ramp = min(Self.rampDuration, (segment.endTime - segment.startTime) / 2)
        let target = fullTransform(ofSegmentAt: index, time: time, cursorPosition: cursorPosition)

        let followsPrevious = index > 0 && connects(index - 1)
        let hasNext = connects(index)

        if ramp > 0, time < segment.startTime + ramp, followsPrevious || segment.startTime > 0 {
            let from = followsPrevious
                ? fullTransform(ofSegmentAt: index - 1, time: time, cursorPosition: cursorPosition)
                : Self.unzoomed
            return blend(from: from, to: target, progress: easeInOutCubic((time - segment.startTime) / ramp))
        }
        if ramp > 0, !hasNext, time > segment.endTime - ramp {
            return blend(from: target, to: Self.unzoomed, progress: easeInOutCubic((time - (segment.endTime - ramp)) / ramp))
        }
        return target
    }

    // MARK: - Internal Helpers

    /// Where segments overlap, the later-starting one wins: earlier segments are
    /// cut into the parts before and after it. The result is sorted and disjoint.
    static func resolvingOverlaps(_ segments: [ZoomSegment]) -> [ZoomSegment] {
        var resolved: [ZoomSegment] = []
        for segment in segments.sorted(by: { $0.startTime < $1.startTime }) {
            resolved = resolved.flatMap { earlier -> [ZoomSegment] in
                guard earlier.startTime < segment.endTime, segment.startTime < earlier.endTime else { return [earlier] }
                var pieces: [ZoomSegment] = []
                if earlier.startTime < segment.startTime {
                    var before = earlier
                    before.endTime = segment.startTime
                    pieces.append(before)
                }
                if segment.endTime < earlier.endTime {
                    var after = earlier
                    after.startTime = segment.endTime
                    pieces.append(after)
                }
                return pieces
            }
            resolved.append(segment)
        }
        return resolved.sorted { $0.startTime < $1.startTime }
    }

    /// Whether the segment after `index` starts right when (or just after) the one at `index` ends.
    private func connects(_ index: Int) -> Bool {
        index + 1 < segments.count
            && segments[index + 1].startTime <= segments[index].endTime + Self.adjacencyTolerance
    }

    /// A connected segment stays in charge until the next one starts, so tiny gaps don't flash to 1×.
    private func effectiveEnd(ofSegmentAt index: Int) -> TimeInterval {
        connects(index) ? max(segments[index].endTime, segments[index + 1].startTime) : segments[index].endTime
    }

    private func fullTransform(
        ofSegmentAt index: Int,
        time: TimeInterval,
        cursorPosition: (x: Double, y: Double)?
    ) -> FrameTransform {
        let segment = segments[index]
        let rawFocus: (x: Double, y: Double)
        switch segment.focusMode {
        case .followCursor:
            rawFocus = followPaths[index]?.position(at: time) ?? cursorPosition ?? (x: 0.5, y: 0.5)
        case .manual(let x, let y):
            rawFocus = (x: x, y: y)
        }
        // translateX/Y carry the normalized focus point (0-1) so the compositor
        // can build the correct scale-around-focus affine transform.
        let focus = edgeSnap(cursor: rawFocus, zoomLevel: segment.zoomLevel)
        return FrameTransform(scale: segment.zoomLevel, translateX: focus.x, translateY: focus.y)
    }

    /// Interpolates scale and focus together, keeping the viewport inside the frame.
    private func blend(from: FrameTransform, to: FrameTransform, progress: Double) -> FrameTransform {
        let scale = from.scale + (to.scale - from.scale) * progress
        let half = 0.5 / scale
        func clamp(_ v: Double) -> Double { min(max(v, half), 1 - half) }
        return FrameTransform(
            scale: scale,
            translateX: clamp(from.translateX + (to.translateX - from.translateX) * progress),
            translateY: clamp(from.translateY + (to.translateY - from.translateY) * progress)
        )
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

    /// Slow start and slow finish.
    private func easeInOutCubic(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}
