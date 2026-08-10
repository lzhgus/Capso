import CoreGraphics
import Testing
@testable import SharedKit

@Suite("ScrollCaptureOverlayPlacement")
struct ScrollCaptureOverlayPlacementTests {
    /// Mimics a 1440×900 display with a 70pt Dock along the bottom.
    private let visibleFrame = CGRect(x: 0, y: 70, width: 1_440, height: 800)
    private let controlsSize = CGSize(width: 300, height: 52)

    @Test("Controls sit below the selection when there is room above the Dock")
    func controlsPreferBelowWhenSpaceAllows() {
        let selection = CGRect(x: 200, y: 300, width: 800, height: 400)

        let frame = ScrollCaptureOverlayPlacement.controlsFrame(
            selectionRect: selection,
            visibleFrame: visibleFrame,
            controlsSize: controlsSize
        )

        #expect(frame == CGRect(x: 450, y: 238, width: 300, height: 52))
        #expect(frame.minY >= visibleFrame.minY)
    }

    @Test("Controls flip above the selection when the Dock would cover them")
    func controlsFlipAboveNearDock() {
        // Selection bottom edge is just above the Dock; below-placement would
        // land inside the Dock exclusion zone (y < 70).
        let selection = CGRect(x: 200, y: 90, width: 800, height: 500)

        let frame = ScrollCaptureOverlayPlacement.controlsFrame(
            selectionRect: selection,
            visibleFrame: visibleFrame,
            controlsSize: controlsSize
        )

        #expect(frame.origin == CGPoint(x: 450, y: 600))
        #expect(frame.minY >= visibleFrame.minY)
        #expect(frame.maxY <= visibleFrame.maxY)
    }

    @Test("Controls stay inside the visible frame when the selection is full height")
    func controlsStayInsideWhenSelectionFillsHeight() {
        let selection = CGRect(x: 100, y: 70, width: 1_200, height: 800)

        let frame = ScrollCaptureOverlayPlacement.controlsFrame(
            selectionRect: selection,
            visibleFrame: visibleFrame,
            controlsSize: controlsSize
        )

        #expect(frame.minX >= visibleFrame.minX)
        #expect(frame.maxX <= visibleFrame.maxX)
        #expect(frame.minY >= visibleFrame.minY)
        #expect(frame.maxY <= visibleFrame.maxY)
    }

    @Test("Controls X is clamped when the selection is near the screen edge")
    func controlsXIsClampedNearEdge() {
        let selection = CGRect(x: 0, y: 300, width: 120, height: 200)

        let frame = ScrollCaptureOverlayPlacement.controlsFrame(
            selectionRect: selection,
            visibleFrame: visibleFrame,
            controlsSize: controlsSize
        )

        #expect(frame.minX == visibleFrame.minX + ScrollCaptureOverlayPlacement.defaultMargin)
        #expect(frame.maxX <= visibleFrame.maxX)
    }

    @Test("Preview prefers the left side of the selection")
    func previewPrefersLeft() {
        let selection = CGRect(x: 400, y: 200, width: 600, height: 500)

        let frame = ScrollCaptureOverlayPlacement.previewFrame(
            selectionRect: selection,
            visibleFrame: visibleFrame
        )

        #expect(frame == CGRect(x: 208, y: 250, width: 180, height: 400))
    }

    @Test("Preview falls back to the right when the left side is blocked")
    func previewFallsBackToRight() {
        let selection = CGRect(x: 20, y: 200, width: 600, height: 500)

        let frame = ScrollCaptureOverlayPlacement.previewFrame(
            selectionRect: selection,
            visibleFrame: visibleFrame
        )

        #expect(frame?.origin.x == 632)
        #expect(frame?.width == 180)
    }

    @Test("Preview is omitted when neither side fits")
    func previewOmittedWhenNoSideFits() {
        let selection = CGRect(x: 8, y: 200, width: 1_424, height: 500)

        let frame = ScrollCaptureOverlayPlacement.previewFrame(
            selectionRect: selection,
            visibleFrame: visibleFrame
        )

        #expect(frame == nil)
    }
}
