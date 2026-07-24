import CoreGraphics
import Testing
@testable import CaptureKit

@Suite("CanvasZoom")
struct CanvasZoomTests {
    private let tolerance: CGFloat = 1e-6

    private func expectClose(_ a: CGPoint, _ b: CGPoint) {
        #expect(abs(a.x - b.x) < tolerance)
        #expect(abs(a.y - b.y) < tolerance)
    }

    // MARK: - clampScale

    @Test("clampScale clamps to the upper bound")
    func clampScaleUpper() {
        #expect(CanvasZoom.clampScale(5.0, min: 0.1, max: 4.0) == 4.0)
    }

    @Test("clampScale clamps to the lower bound")
    func clampScaleLower() {
        #expect(CanvasZoom.clampScale(0.05, min: 0.1, max: 4.0) == 0.1)
    }

    @Test("clampScale passes values already in range")
    func clampScaleInRange() {
        #expect(CanvasZoom.clampScale(1.3, min: 0.1, max: 4.0) == 1.3)
    }

    @Test("clampScale honors a userZoom floor of 1.0")
    func clampScaleUserZoomFloor() {
        #expect(CanvasZoom.clampScale(0.5, min: 1.0, max: 8.0) == 1.0)
    }

    @Test("clampScale honors a userZoom ceiling of 8.0")
    func clampScaleUserZoomCeiling() {
        #expect(CanvasZoom.clampScale(20, min: 1.0, max: 8.0) == 8.0)
    }

    // MARK: - focalOffset (content-origin convention)

    @Test("focalOffset leaves the offset unchanged when the scale does not change")
    func focalOffsetNoChange() {
        let result = CanvasZoom.focalOffset(
            oldScale: 2, newScale: 2,
            focalPoint: CGPoint(x: 100, y: 100),
            currentOffset: CGPoint(x: 0, y: 0)
        )
        expectClose(result, CGPoint(x: 0, y: 0))
    }

    @Test("focalOffset holds the focal point fixed when zooming in x2")
    func focalOffsetZoomIn() {
        let result = CanvasZoom.focalOffset(
            oldScale: 1, newScale: 2,
            focalPoint: CGPoint(x: 100, y: 100),
            currentOffset: CGPoint(x: 0, y: 0)
        )
        expectClose(result, CGPoint(x: -100, y: -100))
    }

    @Test("focalOffset holds the focal point fixed when zooming out x0.5")
    func focalOffsetZoomOut() {
        let result = CanvasZoom.focalOffset(
            oldScale: 2, newScale: 1,
            focalPoint: CGPoint(x: 100, y: 100),
            currentOffset: CGPoint(x: 0, y: 0)
        )
        expectClose(result, CGPoint(x: 50, y: 50))
    }

    @Test("focalOffset accounts for a non-zero current offset")
    func focalOffsetNonZeroCurrent() {
        let result = CanvasZoom.focalOffset(
            oldScale: 1, newScale: 2,
            focalPoint: CGPoint(x: 50, y: 50),
            currentOffset: CGPoint(x: 20, y: 10)
        )
        expectClose(result, CGPoint(x: -10, y: -30))
    }

    @Test("focalOffset guards against a zero old scale")
    func focalOffsetZeroOldScale() {
        let current = CGPoint(x: 7, y: 9)
        let result = CanvasZoom.focalOffset(
            oldScale: 0, newScale: 2,
            focalPoint: CGPoint(x: 50, y: 50),
            currentOffset: current
        )
        expectClose(result, current)
    }

    // MARK: - clampOffset

    @Test("clampOffset leaves an in-range offset untouched")
    func clampOffsetInRange() {
        // content 400, viewport 200 -> valid origin range is [-200, 0]
        let result = CanvasZoom.clampOffset(
            CGPoint(x: -50, y: -50),
            contentSize: CGSize(width: 400, height: 400),
            viewportSize: CGSize(width: 200, height: 200)
        )
        expectClose(result, CGPoint(x: -50, y: -50))
    }

    @Test("clampOffset clamps an over-scrolled positive offset")
    func clampOffsetPositiveClamp() {
        // content 400, viewport 200 -> origin range is [-200, 0]
        let result = CanvasZoom.clampOffset(
            CGPoint(x: 300, y: 300),
            contentSize: CGSize(width: 400, height: 400),
            viewportSize: CGSize(width: 200, height: 200)
        )
        expectClose(result, CGPoint(x: 0, y: 0))
    }

    @Test("clampOffset clamps an over-scrolled negative offset")
    func clampOffsetNegativeClamp() {
        let result = CanvasZoom.clampOffset(
            CGPoint(x: -300, y: -300),
            contentSize: CGSize(width: 400, height: 400),
            viewportSize: CGSize(width: 200, height: 200)
        )
        expectClose(result, CGPoint(x: -200, y: -200))
    }

    @Test("clampOffset centers content smaller than the viewport")
    func clampOffsetCentersSmallContent() {
        let result = CanvasZoom.clampOffset(
            CGPoint(x: 999, y: -999),
            contentSize: CGSize(width: 100, height: 100),
            viewportSize: CGSize(width: 200, height: 200)
        )
        expectClose(result, CGPoint(x: 50, y: 50))
    }
}
