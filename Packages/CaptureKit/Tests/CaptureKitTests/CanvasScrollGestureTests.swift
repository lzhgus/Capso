import Testing
import Foundation
import CoreGraphics
@testable import CaptureKit

@Suite("CanvasScrollGesture")
struct CanvasScrollGestureTests {
    @Test("A plain scroll pans by the event deltas")
    func plainScrollPans() {
        let action = CanvasScrollGesture.action(
            commandHeld: false,
            isMomentum: false,
            verticalDelta: -18,
            horizontalDelta: 4,
            hasPreciseDeltas: true
        )

        #expect(action == .pan(dx: 4, dy: -18))
    }

    @Test("A plain momentum scroll still pans, so flings keep gliding")
    func plainMomentumScrollPans() {
        let action = CanvasScrollGesture.action(
            commandHeld: false,
            isMomentum: true,
            verticalDelta: -6,
            horizontalDelta: 0,
            hasPreciseDeltas: true
        )

        #expect(action == .pan(dx: 0, dy: -6))
    }

    @Test("A plain scroll pans even when the delta is tiny or horizontal")
    func plainScrollPansRegardlessOfShape() {
        let tiny = CanvasScrollGesture.action(
            commandHeld: false,
            isMomentum: false,
            verticalDelta: 0.2,
            horizontalDelta: 0,
            hasPreciseDeltas: true
        )
        let horizontal = CanvasScrollGesture.action(
            commandHeld: false,
            isMomentum: false,
            verticalDelta: 1,
            horizontalDelta: 30,
            hasPreciseDeltas: true
        )

        #expect(tiny == .pan(dx: 0, dy: 0.2))
        #expect(horizontal == .pan(dx: 30, dy: 1))
    }

    @Test("Command-scroll with a usable delta zooms")
    func commandScrollZooms() {
        let action = CanvasScrollGesture.action(
            commandHeld: true,
            isMomentum: false,
            verticalDelta: 10,
            horizontalDelta: 0,
            hasPreciseDeltas: true
        )

        guard case let .zoom(factor) = action else {
            Issue.record("expected a zoom, got \(action)")
            return
        }
        #expect(factor > 1)
    }

    @Test("Command-scroll downward zooms out")
    func commandScrollZoomsOut() {
        let action = CanvasScrollGesture.action(
            commandHeld: true,
            isMomentum: false,
            verticalDelta: -10,
            horizontalDelta: 0,
            hasPreciseDeltas: true
        )

        guard case let .zoom(factor) = action else {
            Issue.record("expected a zoom, got \(action)")
            return
        }
        #expect(factor < 1)
    }

    // The regression this type exists for: these three used to fall through to a
    // pan, so one ⌘-scroll gesture could zoom and then shift the canvas.

    @Test("Command-scroll momentum is ignored, never panned")
    func commandScrollMomentumIsIgnored() {
        let action = CanvasScrollGesture.action(
            commandHeld: true,
            isMomentum: true,
            verticalDelta: 12,
            horizontalDelta: 0,
            hasPreciseDeltas: true
        )

        #expect(action == .ignore)
    }

    @Test("Command-scroll with a delta too small to scale is ignored")
    func commandScrollSmallDeltaIsIgnored() {
        let action = CanvasScrollGesture.action(
            commandHeld: true,
            isMomentum: false,
            verticalDelta: 0.3,
            horizontalDelta: 0,
            hasPreciseDeltas: true
        )

        #expect(action == .ignore)
    }

    @Test("Mostly horizontal command-scroll is ignored")
    func commandScrollHorizontalIsIgnored() {
        let action = CanvasScrollGesture.action(
            commandHeld: true,
            isMomentum: false,
            verticalDelta: 4,
            horizontalDelta: 40,
            hasPreciseDeltas: true
        )

        #expect(action == .ignore)
    }

    @Test("No command-scroll event ever resolves to a pan")
    func commandScrollNeverPans() {
        for vertical in stride(from: -30.0, through: 30.0, by: 0.7) {
            for horizontal in [-40.0, -1.0, 0.0, 1.0, 40.0] {
                for momentum in [true, false] {
                    let action = CanvasScrollGesture.action(
                        commandHeld: true,
                        isMomentum: momentum,
                        verticalDelta: CGFloat(vertical),
                        horizontalDelta: CGFloat(horizontal),
                        hasPreciseDeltas: true
                    )
                    if case .pan = action {
                        Issue.record("⌘-scroll panned at dy=\(vertical) dx=\(horizontal) momentum=\(momentum)")
                    }
                }
            }
        }
    }
}
