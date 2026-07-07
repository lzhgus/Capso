import CoreGraphics
import Testing
@testable import SharedKit

@Suite("CameraPiPPlacement")
struct CameraPiPPlacementTests {
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    private let defaultSize = CGSize(width: 160, height: 120)

    @Test("Restored frame takes precedence over default placement")
    func restoredFrameTakesPrecedence() {
        let restoredFrame = CGRect(x: 100, y: 200, width: 220, height: 180)
        let recordingFrame = CGRect(x: 200, y: 100, width: 400, height: 300)

        let frame = CameraPiPPlacement.frame(
            restoredFrame: restoredFrame,
            defaultSize: defaultSize,
            recordingFrame: recordingFrame,
            visibleFrame: visibleFrame
        )

        #expect(frame == restoredFrame)
    }

    @Test("Restored dimensions are preserved while origin is clamped")
    func restoredDimensionsArePreserved() {
        let restoredFrame = CGRect(x: 950, y: 760, width: 220, height: 180)

        let frame = CameraPiPPlacement.frame(
            restoredFrame: restoredFrame,
            defaultSize: defaultSize,
            recordingFrame: nil,
            visibleFrame: visibleFrame
        )

        #expect(frame.size == restoredFrame.size)
        #expect(frame.origin == CGPoint(x: 772, y: 612))
    }

    @Test("Default fallback uses existing recording-relative placement")
    func defaultFallbackUsesRecordingPlacement() {
        let recordingFrame = CGRect(x: 100, y: 50, width: 500, height: 300)

        let frame = CameraPiPPlacement.frame(
            restoredFrame: nil,
            defaultSize: defaultSize,
            recordingFrame: recordingFrame,
            visibleFrame: visibleFrame
        )

        #expect(frame == CGRect(x: 270, y: 70, width: 160, height: 120))
    }

    @Test("Default fallback uses screen placement without recording frame")
    func defaultFallbackUsesScreenPlacement() {
        let frame = CameraPiPPlacement.frame(
            restoredFrame: nil,
            defaultSize: defaultSize,
            recordingFrame: nil,
            visibleFrame: visibleFrame
        )

        #expect(frame == CGRect(x: 808, y: 32, width: 160, height: 120))
    }

    @Test("Frames are clamped inside visible bounds")
    func framesAreClampedInsideVisibleBounds() {
        let restoredFrame = CGRect(x: -40, y: -30, width: 160, height: 120)

        let frame = CameraPiPPlacement.frame(
            restoredFrame: restoredFrame,
            defaultSize: defaultSize,
            recordingFrame: nil,
            visibleFrame: visibleFrame
        )

        #expect(frame == CGRect(x: 8, y: 8, width: 160, height: 120))
    }
}
