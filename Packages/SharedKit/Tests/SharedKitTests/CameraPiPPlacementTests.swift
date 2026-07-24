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

    @Test("Restart restoration keeps the stored PiP frame when presentation is active")
    func restartRestorationKeepsStoredPiPFrameWhenPresentationIsActive() {
        let presentationFrame = CGRect(x: 50, y: 50, width: 700, height: 500)
        let storedPiPFrame = CGRect(x: 120, y: 140, width: 160, height: 120)

        let state = CameraPiPPlacement.restorationState(
            currentFrame: presentationFrame,
            storedPiPFrame: storedPiPFrame,
            presentationModeActive: true
        )

        #expect(state.restoredFrame == storedPiPFrame)
        #expect(state.presentationModeActive)
    }

    @Test("Restart restoration keeps the current frame when presentation is inactive")
    func restartRestorationKeepsCurrentFrameWhenPresentationIsInactive() {
        let currentFrame = CGRect(x: 120, y: 140, width: 160, height: 120)

        let state = CameraPiPPlacement.restorationState(
            currentFrame: currentFrame,
            storedPiPFrame: CGRect(x: 40, y: 40, width: 700, height: 500),
            presentationModeActive: false
        )

        #expect(state.restoredFrame == currentFrame)
        #expect(!state.presentationModeActive)
    }

    @Test("Initial frame restores presentation mode to the recording frame")
    func initialFrameRestoresPresentationModeToRecordingFrame() {
        let recordingFrame = CGRect(x: 100, y: 80, width: 600, height: 420)
        let state = CameraPiPRestorationState(
            restoredFrame: CGRect(x: 120, y: 140, width: 160, height: 120),
            presentationModeActive: true
        )

        let frame = CameraPiPPlacement.initialFrame(
            restorationState: state,
            defaultSize: defaultSize,
            recordingFrame: recordingFrame,
            visibleFrame: visibleFrame
        )

        #expect(frame == recordingFrame)
    }

    @Test("Fade alpha stays full when feature is disabled")
    func fadeAlphaStaysFullWhenDisabled() {
        #expect(
            CameraPiPPlacement.fadeAlpha(
                enabled: false,
                presentationModeActive: false,
                pointerInside: true
            ) == CameraPiPPlacement.fadeFullAlpha
        )
    }

    @Test("Fade alpha stays full while idle and enabled")
    func fadeAlphaStaysFullWhileIdleAndEnabled() {
        #expect(
            CameraPiPPlacement.fadeAlpha(
                enabled: true,
                presentationModeActive: false,
                pointerInside: false
            ) == CameraPiPPlacement.fadeFullAlpha
        )
    }

    @Test("Fade alpha drops while pointer is over PiP")
    func fadeAlphaDropsWhilePointerInside() {
        #expect(
            CameraPiPPlacement.fadeAlpha(
                enabled: true,
                presentationModeActive: false,
                pointerInside: true
            ) == CameraPiPPlacement.fadeHoverAlpha
        )
    }

    @Test("Fade alpha stays full in presentation mode even when pointer is over PiP")
    func fadeAlphaStaysFullInPresentationMode() {
        #expect(
            CameraPiPPlacement.fadeAlpha(
                enabled: true,
                presentationModeActive: true,
                pointerInside: true
            ) == CameraPiPPlacement.fadeFullAlpha
        )
    }

    @Test("Click-through is independent of fade and only needs option + hover")
    func clickThroughRequiresOptionAndHover() {
        #expect(
            !CameraPiPPlacement.shouldClickThrough(
                clickThroughEnabled: false,
                presentationModeActive: false,
                pointerInside: true
            )
        )
        #expect(
            !CameraPiPPlacement.shouldClickThrough(
                clickThroughEnabled: true,
                presentationModeActive: false,
                pointerInside: false
            )
        )
        #expect(
            CameraPiPPlacement.shouldClickThrough(
                clickThroughEnabled: true,
                presentationModeActive: false,
                pointerInside: true
            )
        )
    }

    @Test("Click-through is never active in fullscreen presentation mode")
    func clickThroughDisabledInPresentationMode() {
        #expect(
            !CameraPiPPlacement.shouldClickThrough(
                clickThroughEnabled: true,
                presentationModeActive: true,
                pointerInside: true
            )
        )
        #expect(
            !CameraPiPPlacement.shouldClickThrough(
                clickThroughEnabled: true,
                presentationModeActive: true,
                pointerInside: false
            )
        )
    }
}
