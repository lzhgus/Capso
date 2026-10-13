import Testing
import Foundation
@testable import EditorKit

@Suite("CursorFollowPath")
struct CursorFollowPathTests {
    /// Cursor samples every 0.05 s from a function of time.
    private func samples(until end: Double, _ position: (Double) -> (Double, Double)) -> [CursorFollowPath.Waypoint] {
        stride(from: 0.0, through: end, by: CursorFollowPath.sampleInterval).map { t in
            let p = position(t)
            return .init(time: t, x: p.0, y: p.1)
        }
    }

    @Test("A cursor that stays put gives one waypoint")
    func stillCursor() {
        let waypoints = CursorFollowPath.waypoints(from: samples(until: 5) { _ in (0.3, 0.4) })
        #expect(waypoints.count == 1)
        #expect(abs(waypoints[0].x - 0.3) < 1e-9 && abs(waypoints[0].y - 0.4) < 1e-9)
    }

    @Test("Small wandering and jitter don't move the camera")
    func jitterIsIgnored() {
        let waypoints = CursorFollowPath.waypoints(from: samples(until: 6) { t in
            (0.5 + 0.12 * sin(t * 3), 0.5 + 0.08 * cos(t * 7))
        })
        #expect(waypoints.count == 1)
    }

    @Test("Moving to a new spot and settling adds a waypoint at the moment it settles")
    func moveAndSettle() {
        let waypoints = CursorFollowPath.waypoints(from: samples(until: 6) { t in
            t < 2 ? (0.2, 0.2) : t < 2.4 ? (0.2 + (t - 2) / 0.4 * 0.6, 0.2 + (t - 2) / 0.4 * 0.5) : (0.8, 0.7)
        })
        #expect(waypoints.count == 2)
        #expect(abs(waypoints[1].x - 0.8) < 0.01 && abs(waypoints[1].y - 0.7) < 0.01)
        #expect(abs(waypoints[1].time - 2.4) < 0.06)
    }

    @Test("The camera holds, pans for the pan duration, and arrives when the cursor settles")
    func panTiming() {
        let path = CursorFollowPath(waypoints: [
            .init(time: 0, x: 0.2, y: 0.2),
            .init(time: 3, x: 0.8, y: 0.6),
        ])
        let panStart = 3 - CursorFollowPath.panDuration
        #expect(path.position(at: panStart - 0.01) == (0.2, 0.2))
        let middle = path.position(at: panStart + CursorFollowPath.panDuration / 2)
        #expect(abs(middle.x - 0.5) < 1e-9 && abs(middle.y - 0.4) < 1e-9)
        #expect(path.position(at: 3) == (0.8, 0.6))
        #expect(path.position(at: 10) == (0.8, 0.6))

        var previous = path.position(at: 0)
        for step in 1...4000 {
            let p = path.position(at: Double(step) * 0.001)
            #expect(hypot(p.x - previous.x, p.y - previous.y) < 0.005)
            previous = p
        }
    }

    @Test("Waypoints closer together than the pan duration are still continuous")
    func closelySpacedWaypoints() {
        let path = CursorFollowPath(waypoints: [
            .init(time: 0, x: 0.2, y: 0.2),
            .init(time: 1.0, x: 0.5, y: 0.5),
            .init(time: 1.3, x: 0.8, y: 0.3),
            .init(time: 1.6, x: 0.3, y: 0.7),
        ])
        var previous = path.position(at: 0)
        for step in 1...3000 {
            let time = Double(step) * 0.001
            let p = path.position(at: time)
            #expect(hypot(p.x - previous.x, p.y - previous.y) < 0.01, "jumped at \(time)")
            previous = p
        }
        #expect(path.position(at: 1.3) == (0.8, 0.3))
        #expect(path.position(at: 2.0) == (0.3, 0.7))
    }
}
