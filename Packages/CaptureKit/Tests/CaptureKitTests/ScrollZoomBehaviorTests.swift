import CoreGraphics
import Testing
@testable import CaptureKit

@Suite("ScrollZoomBehavior")
struct ScrollZoomBehaviorTests {
    @Test("Vertical precise scrolling produces a gentle zoom factor")
    func preciseVerticalScrollingProducesGentleZoomFactor() {
        let zoomIn = ScrollZoomBehavior.scaleFactor(
            verticalDelta: 12,
            horizontalDelta: 0,
            hasPreciseDeltas: true
        )
        let zoomOut = ScrollZoomBehavior.scaleFactor(
            verticalDelta: -12,
            horizontalDelta: 0,
            hasPreciseDeltas: true
        )

        #expect(zoomIn != nil)
        #expect(zoomOut != nil)
        #expect(zoomIn! > 1)
        #expect(zoomOut! < 1)
        #expect(zoomIn! < 1.2)
        #expect(zoomOut! > 0.8)
    }

    @Test("Mouse wheel scrolling gets a stronger per-notch zoom factor")
    func mouseWheelScrollingGetsStrongerZoomFactor() {
        let factor = ScrollZoomBehavior.scaleFactor(
            verticalDelta: 3,
            horizontalDelta: 0,
            hasPreciseDeltas: false
        )

        #expect(factor != nil)
        #expect(factor! > 1.1)
    }

    @Test("Mostly horizontal scrolling is ignored")
    func mostlyHorizontalScrollingIsIgnored() {
        let factor = ScrollZoomBehavior.scaleFactor(
            verticalDelta: 4,
            horizontalDelta: 12,
            hasPreciseDeltas: true
        )

        #expect(factor == nil)
    }
}
