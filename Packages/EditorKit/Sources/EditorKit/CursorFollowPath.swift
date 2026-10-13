// Packages/EditorKit/Sources/EditorKit/CursorFollowPath.swift

import Foundation

/// Where a follow-cursor zoom looks over time. Instead of chasing the cursor
/// every frame, the camera holds on places where the cursor settles and pans
/// between them with an eased move that arrives as the cursor settles.
public struct CursorFollowPath: Sendable {
    struct Waypoint: Equatable {
        var time: TimeInterval
        var x: Double
        var y: Double
    }

    static let sampleInterval: TimeInterval = 0.05
    /// Cursor movement inside this radius (normalized) keeps the camera where it is.
    static let holdRadius: Double = 0.2
    /// The cursor counts as settled once it stays inside this radius…
    static let settleRadius: Double = 0.06
    /// …for at least this long.
    static let settleDuration: TimeInterval = 0.25
    static let panDuration: TimeInterval = 0.7

    let waypoints: [Waypoint]

    public init(timeline: SmoothedCursorTimeline, from start: TimeInterval, to end: TimeInterval) {
        var samples: [Waypoint] = []
        var t = start
        while t <= end {
            let p = timeline.position(at: t)
            samples.append(Waypoint(time: t, x: p.x, y: p.y))
            t += Self.sampleInterval
        }
        self.waypoints = Self.waypoints(from: samples)
    }

    init(waypoints: [Waypoint]) {
        self.waypoints = waypoints
    }

    /// Camera focus at `time`.
    public func position(at time: TimeInterval) -> (x: Double, y: Double) {
        guard let first = waypoints.first else { return (0.5, 0.5) }
        var current = first
        for next in waypoints.dropFirst() {
            // A pan never starts before the previous one arrives, so close waypoints get shorter pans.
            let panStart = max(next.time - Self.panDuration, current.time)
            if time < panStart { break }
            if time < next.time {
                let p = Self.easeInOutCubic((time - panStart) / (next.time - panStart))
                return (current.x + (next.x - current.x) * p, current.y + (next.y - current.y) * p)
            }
            current = next
        }
        return (current.x, current.y)
    }

    static func waypoints(from samples: [Waypoint]) -> [Waypoint] {
        guard let first = samples.first else { return [] }
        var waypoints: [Waypoint] = []
        var anchor = first
        var anchorSum = (x: first.x, y: first.y, count: 1.0)
        var candidate: Waypoint?
        var candidateSum = (x: 0.0, y: 0.0, count: 0.0)

        func commitAnchor() {
            waypoints.append(Waypoint(time: anchor.time, x: anchorSum.x / anchorSum.count, y: anchorSum.y / anchorSum.count))
        }

        for sample in samples.dropFirst() {
            if candidate == nil {
                if distance(sample, anchor) <= holdRadius {
                    anchorSum = (anchorSum.x + sample.x, anchorSum.y + sample.y, anchorSum.count + 1)
                    continue
                }
                candidate = sample
                candidateSum = (sample.x, sample.y, 1)
                continue
            }

            guard let start = candidate else { continue }
            if distance(sample, start) > settleRadius {
                candidate = sample
                candidateSum = (sample.x, sample.y, 1)
                continue
            }
            candidateSum = (candidateSum.x + sample.x, candidateSum.y + sample.y, candidateSum.count + 1)
            guard sample.time - start.time >= settleDuration else { continue }

            let settled = Waypoint(time: start.time, x: candidateSum.x / candidateSum.count, y: candidateSum.y / candidateSum.count)
            let current = Waypoint(time: anchor.time, x: anchorSum.x / anchorSum.count, y: anchorSum.y / anchorSum.count)
            if distance(settled, current) >= settleRadius {
                commitAnchor()
                anchor = settled
                anchorSum = candidateSum
            }
            candidate = nil
        }
        commitAnchor()
        return waypoints
    }

    private static func distance(_ a: Waypoint, _ b: Waypoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func easeInOutCubic(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}
