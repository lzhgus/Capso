import Testing
import CoreGraphics
@testable import EditorKit

@Suite("ZoomInterpolator")
struct ZoomInterpolatorTests {

    private static let frameSize = CGSize(width: 1920, height: 1080)

    private func makeInterpolator(segments: [ZoomSegment]) -> ZoomInterpolator {
        ZoomInterpolator(segments: segments, frameSize: Self.frameSize)
    }

    @Test("No zoom segments returns identity transform")
    func noSegmentsReturnsIdentity() {
        let interp = makeInterpolator(segments: [])
        let t = interp.transform(at: 5.0, cursorPosition: (x: 0.5, y: 0.5))
        #expect(t == .identity)
    }

    @Test("Inside zoom segment at full strength returns full zoom")
    func insideSegmentFullStrength() {
        let segment = ZoomSegment(startTime: 2.0, endTime: 8.0, zoomLevel: 2.0, focusMode: .manual(x: 0.5, y: 0.5))
        let interp = makeInterpolator(segments: [segment])
        let t = interp.transform(at: 5.0, cursorPosition: nil)
        #expect(abs(t.scale - 2.0) < 1e-9)
    }

    @Test("Before zoom segment returns identity")
    func beforeSegmentReturnsIdentity() {
        let segment = ZoomSegment(startTime: 5.0, endTime: 10.0, zoomLevel: 2.0)
        let interp = makeInterpolator(segments: [segment])
        let t = interp.transform(at: 1.0, cursorPosition: (x: 0.5, y: 0.5))
        #expect(t == .identity)
    }

    @Test("After zoom segment returns identity")
    func afterSegmentReturnsIdentity() {
        let segment = ZoomSegment(startTime: 2.0, endTime: 5.0, zoomLevel: 2.0)
        let interp = makeInterpolator(segments: [segment])
        let t = interp.transform(at: 8.0, cursorPosition: (x: 0.5, y: 0.5))
        #expect(abs(t.scale - 1.0) < 1e-9)
    }

    @Test("Zoom-in transition is gradual")
    func zoomInTransitionIsGradual() {
        let segment = ZoomSegment(startTime: 2.0, endTime: 8.0, zoomLevel: 2.0, focusMode: .manual(x: 0.5, y: 0.5))
        let interp = makeInterpolator(segments: [segment])
        let earlyTransform = interp.transform(at: 2.1, cursorPosition: nil)
        #expect(earlyTransform.scale > 1.0)
        #expect(earlyTransform.scale < 2.0)
        let laterTransform = interp.transform(at: 2.5, cursorPosition: nil)
        #expect(laterTransform.scale > earlyTransform.scale)
    }

    @Test("Manual focus at off-center position produces non-center focus point")
    func manualFocusOffCenter() {
        // Focus at (0.2, 0.8) → after edge-snap, focus.x < 0.5, focus.y > 0.5
        let segment = ZoomSegment(startTime: 0.0, endTime: 10.0, zoomLevel: 2.0, focusMode: .manual(x: 0.2, y: 0.8))
        let interp = makeInterpolator(segments: [segment])
        let t = interp.transform(at: 5.0, cursorPosition: nil)
        // translateX/Y carry the focus point (0-1). Focus left of center → x < 0.5
        #expect(t.translateX < 0.5)
        // Focus below center → y > 0.5
        #expect(t.translateY > 0.5)
    }

    @Test("Follow cursor mode uses cursor position")
    func followCursorUsesCursorPosition() {
        let segment = ZoomSegment(startTime: 0.0, endTime: 10.0, zoomLevel: 2.0, focusMode: .followCursor)
        let interp = makeInterpolator(segments: [segment])
        let t1 = interp.transform(at: 5.0, cursorPosition: (x: 0.3, y: 0.5))
        let t2 = interp.transform(at: 5.0, cursorPosition: (x: 0.7, y: 0.5))
        #expect(t1.translateX != t2.translateX)
    }

    @Test("Edge snap clamps focus to valid viewport range")
    func edgeSnapClampsFocus() {
        // Focus at corner (0.0, 0.0) with 2x → edge-snapped to viewportHalf = 0.25
        let segment = ZoomSegment(startTime: 0.0, endTime: 10.0, zoomLevel: 2.0, focusMode: .manual(x: 0.0, y: 0.0))
        let interp = makeInterpolator(segments: [segment])
        let t = interp.transform(at: 5.0, cursorPosition: nil)
        // Focus clamped to 0.25 (viewportHalf = 0.5 / 2.0)
        #expect(abs(t.translateX - 0.25) < 1e-9)
        #expect(abs(t.translateY - 0.25) < 1e-9)
    }

    // MARK: - Transitions

    private func scale(_ interp: ZoomInterpolator, at time: Double) -> Double {
        interp.transform(at: time, cursorPosition: nil).scale
    }

    @Test("Zoom-out finishes inside the segment and nothing lingers after it")
    func zoomOutInsideSegment() {
        let interp = makeInterpolator(segments: [
            ZoomSegment(startTime: 2, endTime: 8, zoomLevel: 2, focusMode: .manual(x: 0.5, y: 0.5)),
        ])
        #expect(abs(scale(interp, at: 8 - ZoomInterpolator.rampDuration) - 2) < 1e-9)
        #expect(scale(interp, at: 7.999) < 1.001)
        #expect(interp.transform(at: 8.0, cursorPosition: nil) == .identity)
        #expect(interp.transform(at: 8.3, cursorPosition: nil) == .identity)
    }

    @Test("Ramps ease in and out symmetrically")
    func easeInOut() {
        let interp = makeInterpolator(segments: [
            ZoomSegment(startTime: 2, endTime: 8, zoomLevel: 3, focusMode: .manual(x: 0.5, y: 0.5)),
        ])
        let ramp = ZoomInterpolator.rampDuration
        #expect(abs(scale(interp, at: 2 + ramp / 2) - 2) < 1e-9)
        let early = scale(interp, at: 2 + ramp * 0.1) - 1
        let late = 3 - scale(interp, at: 2 + ramp * 0.9)
        #expect(abs(early - late) < 1e-9)
        #expect(early < 0.02)
    }

    @Test("Short segments split their length between the two ramps")
    func shortSegment() {
        let interp = makeInterpolator(segments: [
            ZoomSegment(startTime: 2, endTime: 3, zoomLevel: 2, focusMode: .manual(x: 0.5, y: 0.5)),
        ])
        #expect(abs(scale(interp, at: 2.5) - 2) < 1e-9)
        #expect(scale(interp, at: 2.25) > 1.4 && scale(interp, at: 2.25) < 1.6)
    }

    @Test("Back-to-back segments move between zooms without returning to 1x")
    func backToBack() {
        let interp = makeInterpolator(segments: [
            ZoomSegment(startTime: 2, endTime: 5, zoomLevel: 2, focusMode: .manual(x: 0.3, y: 0.5)),
            ZoomSegment(startTime: 5, endTime: 9, zoomLevel: 3, focusMode: .manual(x: 0.7, y: 0.5)),
        ])
        var previous = scale(interp, at: 4.5)
        for step in 1...100 {
            let s = scale(interp, at: 4.5 + Double(step) * 0.01)
            #expect(s >= 2 - 1e-9)
            #expect(abs(s - previous) < 0.05)
            previous = s
        }
        #expect(abs(scale(interp, at: 5 + ZoomInterpolator.rampDuration) - 3) < 1e-9)
    }

    @Test("A segment at the very start is fully zoomed from the first frame")
    func segmentAtStart() {
        let interp = makeInterpolator(segments: [
            ZoomSegment(startTime: 0, endTime: 4, zoomLevel: 2, focusMode: .manual(x: 0.5, y: 0.5)),
        ])
        #expect(abs(scale(interp, at: 0) - 2) < 1e-9)
    }

    @Test("The viewport stays inside the frame during a ramp toward an edge")
    func viewportInsideFrameDuringRamp() {
        let interp = makeInterpolator(segments: [
            ZoomSegment(startTime: 1, endTime: 6, zoomLevel: 2.5, focusMode: .manual(x: 0.0, y: 1.0)),
        ])
        for step in 0...100 {
            let t = interp.transform(at: 1 + Double(step) * 0.01, cursorPosition: nil)
            let half = 0.5 / t.scale
            #expect(t.translateX >= half - 1e-9 && t.translateX <= 1 - half + 1e-9)
            #expect(t.translateY >= half - 1e-9 && t.translateY <= 1 - half + 1e-9)
        }
    }

    @Test("Segments separated by a tiny gap or overlapping never dip below the lower zoom", arguments: [
        (5.0, 5.03),
        (5.0, 4.2),
    ])
    func nearlyTouchingOrOverlapping(firstEnd: Double, secondStart: Double) {
        let interp = makeInterpolator(segments: [
            ZoomSegment(startTime: 2, endTime: firstEnd, zoomLevel: 2, focusMode: .manual(x: 0.3, y: 0.5)),
            ZoomSegment(startTime: secondStart, endTime: 9, zoomLevel: 3, focusMode: .manual(x: 0.7, y: 0.5)),
        ])
        for step in 0...300 {
            let time = 3.0 + Double(step) * 0.01
            #expect(scale(interp, at: time) >= 2 - 1e-9, "dipped at \(time)")
        }
    }

    @Test("Scale never jumps when segments overlap, start during a ramp, or nest", arguments: [
        [(2.0, 8.0, 2.0), (2.3, 9.0, 3.0)],
        [(2.0, 9.0, 2.0), (4.0, 5.0, 3.0)],
        [(2.0, 6.0, 3.0), (5.0, 9.0, 2.0)],
    ])
    func noJumps(spec: [(Double, Double, Double)]) {
        let interp = makeInterpolator(segments: spec.map {
            ZoomSegment(startTime: $0.0, endTime: $0.1, zoomLevel: $0.2, focusMode: .manual(x: 0.5, y: 0.5))
        })
        var previous = scale(interp, at: 1.0)
        for step in 1...10_000 {
            let time = 1.0 + Double(step) * 0.001
            let s = scale(interp, at: time)
            #expect(abs(s - previous) < 0.02, "jumped at \(time) from \(previous) to \(s)")
            previous = s
        }
    }
}
