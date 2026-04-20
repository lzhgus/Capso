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
}
