import CoreGraphics
import Testing
@testable import SharedKit

@Suite("QuickAccessPreviewGeometry")
struct QuickAccessPreviewGeometryTests {
    @Test("Wide captures are constrained by available width")
    func wideCaptureFitsAvailableWidth() {
        let size = QuickAccessPreviewGeometry.contentSize(
            imagePixelSize: CGSize(width: 4000, height: 2000),
            availableSize: CGSize(width: 1000, height: 800),
            maxViewportFraction: 0.8
        )

        #expect(size.width == 800)
        #expect(size.height == 400)
    }

    @Test("Tall captures are constrained by available height")
    func tallCaptureFitsAvailableHeight() {
        let size = QuickAccessPreviewGeometry.contentSize(
            imagePixelSize: CGSize(width: 1000, height: 4000),
            availableSize: CGSize(width: 1000, height: 800),
            maxViewportFraction: 0.8
        )

        #expect(size.width == 160)
        #expect(size.height == 640)
    }
}
