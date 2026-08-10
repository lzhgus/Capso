import CoreGraphics
import Testing
@testable import CaptureKit

@Suite("ScrollCaptureGeometry")
struct ScrollCaptureGeometryTests {
    /// 1440×900 display with a 70pt Dock along the bottom and a 25pt menu bar.
    private let screenFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
    private let visibleFrame = CGRect(x: 0, y: 70, width: 1_440, height: 805)

    @Test("Selection overlapping the Dock is cropped above the Dock")
    func clampsBottomEdgeAboveDock() {
        let selection = CGRect(x: 100, y: 0, width: 800, height: 600)

        let clamped = ScrollCaptureGeometry.clampedScreenLocalSelection(
            selectionRect: selection,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )

        #expect(clamped == CGRect(x: 100, y: 70, width: 800, height: 530))
    }

    @Test("Selection fully inside the visible frame is unchanged")
    func leavesInBoundsSelectionUnchanged() {
        let selection = CGRect(x: 200, y: 120, width: 700, height: 400)

        let clamped = ScrollCaptureGeometry.clampedScreenLocalSelection(
            selectionRect: selection,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )

        #expect(clamped == selection)
    }

    @Test("Selection only covering the Dock is rejected")
    func rejectsDockOnlySelection() {
        let selection = CGRect(x: 0, y: 0, width: 1_440, height: 60)

        let clamped = ScrollCaptureGeometry.clampedScreenLocalSelection(
            selectionRect: selection,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )

        #expect(clamped.isNull || clamped.isEmpty)
    }

    @Test("Top-left conversion flips Y against the full screen height")
    func topLeftConversionUsesScreenHeight() {
        let selection = CGRect(x: 100, y: 70, width: 800, height: 530)

        let topLeft = ScrollCaptureGeometry.topLeftCaptureRect(
            screenLocalSelection: selection,
            screenHeight: screenFrame.height
        )

        #expect(topLeft == CGRect(x: 100, y: 300, width: 800, height: 530))
    }
}
