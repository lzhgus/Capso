import CoreGraphics
import Testing
@testable import SharedKit

@Suite("AnnotationEditorWindowGeometry")
struct AnnotationEditorWindowGeometryTests {
    @Test("Converts Retina pixels to points before fitting the viewport")
    func retinaPixelsAreConvertedToPoints() {
        let size = AnnotationEditorWindowGeometry.contentSize(
            imagePixelSize: CGSize(width: 2000, height: 1000),
            backingScaleFactor: 2,
            visibleSize: CGSize(width: 1400, height: 900),
            chromeHeight: 110,
            maxViewportFraction: 0.8
        )

        // 2000×1000 px @2x → 1000×500 pt, fits at 1.0 within 1120×610 budget.
        #expect(size.width == 1000)
        #expect(size.height == 610)
    }

    @Test("Treats 1x captures as already being in points")
    func nonRetinaPixelsStayInPoints() {
        let size = AnnotationEditorWindowGeometry.contentSize(
            imagePixelSize: CGSize(width: 800, height: 400),
            backingScaleFactor: 1,
            visibleSize: CGSize(width: 1400, height: 900),
            chromeHeight: 110,
            maxViewportFraction: 0.8
        )

        #expect(size.width == 800)
        #expect(size.height == 510)
    }

    @Test("Downscales wide captures to the viewport width budget")
    func wideCaptureIsWidthConstrained() {
        let size = AnnotationEditorWindowGeometry.contentSize(
            imagePixelSize: CGSize(width: 4000, height: 1000),
            backingScaleFactor: 2,
            visibleSize: CGSize(width: 1000, height: 800),
            chromeHeight: 100,
            maxViewportFraction: 0.8
        )

        // 2000×500 pt → scale by 800/2000 = 0.4 → 800×200 + chrome 100.
        #expect(size.width == 800)
        #expect(size.height == 300)
    }

    @Test("Downscales tall captures to the viewport height budget")
    func tallCaptureIsHeightConstrained() {
        let size = AnnotationEditorWindowGeometry.contentSize(
            imagePixelSize: CGSize(width: 1000, height: 4000),
            backingScaleFactor: 2,
            visibleSize: CGSize(width: 1000, height: 800),
            chromeHeight: 100,
            maxViewportFraction: 0.8
        )

        // 500×2000 pt → height budget 540 → scale 540/2000 = 0.27 → 135×540 + 100.
        #expect(abs(size.width - 135) < 0.001)
        #expect(abs(size.height - 640) < 0.001)
    }

    @Test("Centers a frame inside the visible display rect")
    func centersFrameInVisibleRect() {
        let frame = AnnotationEditorWindowGeometry.centeredFrame(
            size: CGSize(width: 400, height: 300),
            in: CGRect(x: 100, y: 50, width: 1200, height: 800)
        )

        #expect(frame == CGRect(x: 500, y: 300, width: 400, height: 300))
    }

    @Test("Rejects invalid geometry")
    func invalidGeometry() {
        #expect(
            AnnotationEditorWindowGeometry.contentSize(
                imagePixelSize: .zero,
                backingScaleFactor: 2,
                visibleSize: CGSize(width: 1000, height: 800),
                chromeHeight: 110
            ) == .zero
        )
        #expect(
            AnnotationEditorWindowGeometry.centeredFrame(
                size: CGSize(width: 100, height: 100),
                in: .zero
            ) == .zero
        )
    }
}
