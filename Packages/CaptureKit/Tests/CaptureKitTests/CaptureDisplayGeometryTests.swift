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

    @Test("Positions preset badge below the physical top on screens without a notch")
    func presetBadgeYWithoutSafeAreaInset() {
        let y = CaptureDisplayGeometry.presetBadgeY(
            viewHeight: 1117,
            badgeHeight: 29,
            safeAreaTopInset: 0
        )

        #expect(y == 1068)
    }

    @Test("Positions preset badge below the notch safe area")
    func presetBadgeYWithSafeAreaInset() {
        let y = CaptureDisplayGeometry.presetBadgeY(
            viewHeight: 1117,
            badgeHeight: 29,
            safeAreaTopInset: 32
        )

        #expect(y == 992)
    }

    @Test("Rejects invalid geometry")
    func invalidGeometry() {
        #expect(CaptureDisplayGeometry.displayScale(
            imageSize: CGSize(width: 0, height: 480),
            screenRect: CGRect(x: 0, y: 0, width: 400, height: 240)
        ) == nil)
    }

    @Test("Maps a screen-local selection to frozen screenshot pixels")
    func frozenImageCropRect() {
        let crop = CaptureDisplayGeometry.frozenImageCropRect(
            screenLocalRect: CGRect(x: 120, y: 180, width: 320, height: 160),
            screenSize: CGSize(width: 800, height: 600),
            imageSize: CGSize(width: 1600, height: 1200)
        )

        #expect(crop == CGRect(x: 240, y: 520, width: 640, height: 320))
    }

    @Test("Rejects invalid frozen screenshot crop geometry")
    func invalidFrozenImageCropRect() {
        let crop = CaptureDisplayGeometry.frozenImageCropRect(
            screenLocalRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            screenSize: .zero,
            imageSize: CGSize(width: 1600, height: 1200)
        )

        #expect(crop.isNull)
    }

    @Test("Converts global top-left window frame to display-local rect")
    func displayLocalRectFromGlobalWindowFrame() {
        let rect = CaptureDisplayGeometry.displayLocalRect(
            fromGlobalTopLeftRect: CGRect(x: 1540, y: 140, width: 500, height: 320),
            displayBounds: CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        )

        #expect(rect == CGRect(x: 100, y: 140, width: 500, height: 320))
    }

    @Test("Clamps display-local window frame to visible display area")
    func displayLocalRectClampsPartiallyOffscreenWindow() {
        let rect = CaptureDisplayGeometry.displayLocalRect(
            fromGlobalTopLeftRect: CGRect(x: -20, y: 10, width: 100, height: 80),
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        #expect(rect == CGRect(x: 0, y: 10, width: 80, height: 80))
    }
}
