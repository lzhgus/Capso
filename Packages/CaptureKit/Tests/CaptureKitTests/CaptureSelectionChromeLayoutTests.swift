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

    @Test("HUD prefers above and falls back inside near the top edge")
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
        ) == CGPoint(x: 110, y: 756))
    }
}
