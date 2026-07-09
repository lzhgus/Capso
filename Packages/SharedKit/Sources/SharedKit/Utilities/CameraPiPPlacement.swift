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
