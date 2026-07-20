import CoreGraphics

public struct CameraPiPRestorationState: Equatable {
    public let restoredFrame: CGRect
    public let presentationModeActive: Bool

    public init(restoredFrame: CGRect, presentationModeActive: Bool) {
        self.restoredFrame = restoredFrame
        self.presentationModeActive = presentationModeActive
    }
}

public enum CameraPiPPlacement {
    public static let defaultScreenMargin: CGFloat = 32
    public static let recordingBottomOffset: CGFloat = 20
    public static let visibleMargin: CGFloat = 8

    /// Opacity applied to the camera PiP when fade-on-hover is enabled and the pointer is over it
    /// (so content behind the PiP is readable without moving the window).
    public static let fadeHoverAlpha: CGFloat = 0.18

    /// Full opacity for the camera PiP (idle, presentation mode, or feature disabled).
    public static let fadeFullAlpha: CGFloat = 1.0

    /// Target window opacity for optional fade-on-hover behavior.
    /// PiP stays fully solid until the pointer enters it, then becomes nearly transparent.
    /// Fullscreen / presentation mode always stays fully opaque.
    public static func fadeAlpha(
        enabled: Bool,
        presentationModeActive: Bool,
        pointerInside: Bool
    ) -> CGFloat {
        guard enabled, !presentationModeActive else { return fadeFullAlpha }
        return pointerInside ? fadeHoverAlpha : fadeFullAlpha
    }

    /// Whether the small camera PiP should ignore mouse events so clicks hit content behind it.
    /// Independent of fade-on-hover. Requires click-through enabled, pointer over the PiP, and
    /// **not** fullscreen presentation mode (fullscreen always stays interactive).
    public static func shouldClickThrough(
        clickThroughEnabled: Bool,
        presentationModeActive: Bool,
        pointerInside: Bool
    ) -> Bool {
        // Fullscreen / presentation mode always receives clicks (never click-through).
        guard !presentationModeActive else { return false }
        guard clickThroughEnabled, pointerInside else { return false }
        return true
    }

    public static func frame(
        restoredFrame: CGRect?,
        defaultSize: CGSize,
        recordingFrame: CGRect?,
        visibleFrame: CGRect
    ) -> CGRect {
        if let restoredFrame {
            return clampedFrame(restoredFrame, in: visibleFrame)
        }

        return clampedFrame(
            defaultFrame(
                size: defaultSize,
                recordingFrame: recordingFrame,
                visibleFrame: visibleFrame
            ),
            in: visibleFrame
        )
    }

    public static func restorationState(
        currentFrame: CGRect,
        storedPiPFrame: CGRect?,
        presentationModeActive: Bool
    ) -> CameraPiPRestorationState {
        CameraPiPRestorationState(
            restoredFrame: presentationModeActive ? (storedPiPFrame ?? currentFrame) : currentFrame,
            presentationModeActive: presentationModeActive
        )
    }

    public static func initialFrame(
        restorationState: CameraPiPRestorationState?,
        defaultSize: CGSize,
        recordingFrame: CGRect?,
        visibleFrame: CGRect
    ) -> CGRect {
        if restorationState?.presentationModeActive == true, let recordingFrame {
            return recordingFrame
        }

        return frame(
            restoredFrame: restorationState?.restoredFrame,
            defaultSize: defaultSize,
            recordingFrame: recordingFrame,
            visibleFrame: visibleFrame
        )
    }

    public static func defaultFrame(
        size: CGSize,
        recordingFrame: CGRect?,
        visibleFrame: CGRect
    ) -> CGRect {
        let origin: CGPoint
        if let recordingFrame {
            origin = CGPoint(
                x: recordingFrame.midX - size.width / 2,
                y: recordingFrame.minY + recordingBottomOffset
            )
        } else {
            origin = CGPoint(
                x: visibleFrame.maxX - size.width - defaultScreenMargin,
                y: visibleFrame.minY + defaultScreenMargin
            )
        }

        return CGRect(origin: origin, size: size)
    }

    public static func clampedFrame(
        _ frame: CGRect,
        in visibleFrame: CGRect,
        margin: CGFloat = visibleMargin
    ) -> CGRect {
        var clampedFrame = frame
        clampedFrame.origin.x = clampedOrigin(
            value: frame.origin.x,
            lowerBound: visibleFrame.minX + margin,
            upperBound: visibleFrame.maxX - frame.width - margin
        )
        clampedFrame.origin.y = clampedOrigin(
            value: frame.origin.y,
            lowerBound: visibleFrame.minY + margin,
            upperBound: visibleFrame.maxY - frame.height - margin
        )
        return clampedFrame
    }

    private static func clampedOrigin(
        value: CGFloat,
        lowerBound: CGFloat,
        upperBound: CGFloat
    ) -> CGFloat {
        guard lowerBound <= upperBound else { return lowerBound }
        return max(lowerBound, min(value, upperBound))
    }
}
