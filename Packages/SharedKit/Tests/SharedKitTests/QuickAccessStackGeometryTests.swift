import CoreGraphics
import Testing
@testable import SharedKit

@Suite("QuickAccessStackGeometry")
struct QuickAccessStackGeometryTests {
    private let screenFrame = CGRect(x: 100, y: 50, width: 1200, height: 800)
    private let visibleFrame = CGRect(x: 100, y: 90, width: 1160, height: 740)
    private let previewSize = CGSize(width: 288, height: 200)

    @Test("A single center-screen preview is centered on the display")
    func singlePreviewIsCentered() {
        let frame = QuickAccessStackGeometry.frame(
            position: .centerScreen,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            windowSize: previewSize,
            stackIndex: 0,
            stackCount: 1
        )

        #expect(frame.midX == screenFrame.midX)
        #expect(frame.midY == screenFrame.midY)
    }

    @Test("A two-preview stack is centered as a group")
    func twoPreviewStackIsCentered() {
        let firstFrame = QuickAccessStackGeometry.frame(
            position: .centerScreen,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            windowSize: previewSize,
            stackIndex: 0,
            stackCount: 2
        )
        let secondFrame = QuickAccessStackGeometry.frame(
            position: .centerScreen,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            windowSize: previewSize,
            stackIndex: 1,
            stackCount: 2
        )

        let stackMidY = (firstFrame.minY + secondFrame.maxY) / 2
        #expect(firstFrame.midX == screenFrame.midX)
        #expect(secondFrame.midX == screenFrame.midX)
        #expect(stackMidY == screenFrame.midY)
        #expect(secondFrame.minY - firstFrame.maxY == 12)
    }

    @Test("Corner stacks retain their edge inset and bottom-up ordering")
    func bottomCornerPlacement() {
        let leftFrame = QuickAccessStackGeometry.frame(
            position: .bottomLeft,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            windowSize: previewSize,
            stackIndex: 1,
            stackCount: 2
        )
        let rightFrame = QuickAccessStackGeometry.frame(
            position: .bottomRight,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            windowSize: previewSize,
            stackIndex: 0,
            stackCount: 2
        )

        #expect(leftFrame.minX == visibleFrame.minX + 16)
        #expect(leftFrame.minY == visibleFrame.minY + previewSize.height + 28)
        #expect(rightFrame.maxX == visibleFrame.maxX - 16)
        #expect(rightFrame.minY == visibleFrame.minY + 16)
    }
}
