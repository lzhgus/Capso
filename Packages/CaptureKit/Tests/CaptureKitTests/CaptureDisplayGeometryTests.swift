import Testing
import CoreGraphics
@testable import CaptureKit

@Suite("CaptureDisplayGeometry")
struct CaptureDisplayGeometryTests {
    @Test("Converts top-left capture rect to bottom-left screen-local rect")
    func screenLocalRectFromCaptureRect() {
        let captureRect = CGRect(x: 120, y: 80, width: 400, height: 240)

        let rect = CaptureDisplayGeometry.screenLocalRect(
            fromTopLeftCaptureRect: captureRect,
            screenHeight: 900
        )

        #expect(rect == CGRect(x: 120, y: 580, width: 400, height: 240))
    }

    @Test("Computes display scale from image pixels to screen points")
    func displayScaleForImageInScreenRect() {
        let scale = CaptureDisplayGeometry.displayScale(
            imageSize: CGSize(width: 800, height: 480),
            screenRect: CGRect(x: 0, y: 0, width: 400, height: 240)
        )

        #expect(scale == 0.5)
    }

    @Test("Rejects invalid geometry")
    func invalidGeometry() {
        #expect(CaptureDisplayGeometry.displayScale(
            imageSize: CGSize(width: 0, height: 480),
            screenRect: CGRect(x: 0, y: 0, width: 400, height: 240)
        ) == nil)
    }
}
