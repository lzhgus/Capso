import CoreGraphics
import Testing
@testable import CaptureKit

@Suite("Capture selection chrome layout")
struct CaptureSelectionChromeLayoutTests {
    @Test("Regular selections expose all eight resize handles")
    func regularHandles() {
        #expect(CaptureSelectionChromeLayout.visibleHandles(
            for: CGSize(width: 320, height: 180),
            isFixedSize: false
        ).count == 8)
    }

    @Test("Small selections keep only corner handles")
    func smallHandles() {
        #expect(CaptureSelectionChromeLayout.visibleHandles(
            for: CGSize(width: 79, height: 180),
            isFixedSize: false
        ) == [.topLeft, .topRight, .bottomRight, .bottomLeft])
        #expect(CaptureSelectionChromeLayout.visibleHandles(
            for: CGSize(width: 180, height: 79),
            isFixedSize: false
        ) == [.topLeft, .topRight, .bottomRight, .bottomLeft])
    }

    @Test("The 80-by-80 boundary exposes all eight resize handles")
    func handleThresholdBoundary() {
        #expect(CaptureSelectionChromeLayout.visibleHandles(
            for: CGSize(width: 80, height: 80),
            isFixedSize: false
        ) == [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left])
    }

    @Test("Fixed-size selections hide resize handles")
    func fixedHandles() {
        #expect(CaptureSelectionChromeLayout.visibleHandles(
            for: CGSize(width: 320, height: 180),
            isFixedSize: true
        ).isEmpty)
    }

    @Test("Dimension text uses the multiplication sign")
    func dimensionText() {
        #expect(CaptureSelectionChromeLayout.dimensionText(
            for: CGSize(width: 1_139.6, height: 563.7)
        ) == "1140 × 564")
    }

    @Test("HUD prefers above and falls below near the top edge")
    func hudPlacement() {
        let bounds = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let hud = CGSize(width: 92, height: 24)
        #expect(CaptureSelectionChromeLayout.dimensionHUDOrigin(
            selectionRect: CGRect(x: 100, y: 100, width: 500, height: 300),
            hudSize: hud,
            in: bounds
        ) == CGPoint(x: 100, y: 408))
        #expect(CaptureSelectionChromeLayout.dimensionHUDOrigin(
            selectionRect: CGRect(x: 100, y: 500, width: 500, height: 290),
            hudSize: hud,
            in: bounds
        ) == CGPoint(x: 100, y: 468))
    }

    @Test("Tiny selections at the top edge place the HUD below without overlap")
    func tinyTopEdgeHUDPlacement() {
        let bounds = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let hud = CGSize(width: 92, height: 24)
        let selection = CGRect(x: 100, y: 776, width: 120, height: 24)
        let origin = CaptureSelectionChromeLayout.dimensionHUDOrigin(
            selectionRect: selection,
            hudSize: hud,
            in: bounds
        )

        #expect(origin == CGPoint(x: 100, y: 744))
        #expect(CGRect(origin: origin, size: hud).maxY <= selection.minY)
    }

    @Test("HUD falls inside when neither outside placement fits")
    func insideHUDPlacement() {
        #expect(CaptureSelectionChromeLayout.dimensionHUDOrigin(
            selectionRect: CGRect(x: 100, y: 4, width: 500, height: 792),
            hudSize: CGSize(width: 92, height: 24),
            in: CGRect(x: 0, y: 0, width: 1_200, height: 800)
        ) == CGPoint(x: 110, y: 762))
    }
}
