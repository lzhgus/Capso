import CoreGraphics

/// Geometry for the key-press HUD relative to the active **display/area** recording frame
/// (AppKit bottom-left coordinates). Window-target recording is out of scope for this helper.
public enum KeyPressOverlayPlacement {
    public static let defaultMargin: CGFloat = 24
    public static let defaultSize = CGSize(width: 80, height: 40)

    /// Bottom-leading placement inside the recording frame.
    public static func defaultOrigin(
        recordingFrame: CGRect,
        size: CGSize = defaultSize,
        margin: CGFloat = defaultMargin
    ) -> CGPoint {
        CGPoint(
            x: recordingFrame.minX + margin,
            y: recordingFrame.minY + margin
        )
    }

    /// Resolve origin from a saved offset within the recording frame (origin-relative),
    /// falling back to the default corner when no offset is stored.
    public static func origin(
        savedOffsetX: Double?,
        savedOffsetY: Double?,
        recordingFrame: CGRect,
        size: CGSize = defaultSize,
        margin: CGFloat = defaultMargin
    ) -> CGPoint {
        let proposed: CGPoint
        if let savedOffsetX, let savedOffsetY {
            proposed = CGPoint(
                x: recordingFrame.minX + CGFloat(savedOffsetX),
                y: recordingFrame.minY + CGFloat(savedOffsetY)
            )
        } else {
            proposed = defaultOrigin(recordingFrame: recordingFrame, size: size, margin: margin)
        }
        return clampedFrame(
            CGRect(origin: proposed, size: size),
            in: recordingFrame,
            margin: margin
        ).origin
    }

    /// Offset of a window origin relative to the recording frame (for persistence).
    public static func offset(
        windowOrigin: CGPoint,
        recordingFrame: CGRect
    ) -> (x: Double, y: Double) {
        (
            Double(windowOrigin.x - recordingFrame.minX),
            Double(windowOrigin.y - recordingFrame.minY)
        )
    }

    /// Keep the HUD fully inside the recording frame (hard clamp for area capture inclusion).
    public static func clampedFrame(
        _ frame: CGRect,
        in recordingFrame: CGRect,
        margin: CGFloat = defaultMargin
    ) -> CGRect {
        let recordingFrame = recordingFrame.standardized
        var result = frame.standardized
        result.size.width = max(0, min(result.width, recordingFrame.width))
        result.size.height = max(0, min(result.height, recordingFrame.height))

        // Preserve the requested margin when it fits. For a very small capture
        // region, collapse it just enough to keep the entire HUD in-frame.
        let horizontalMargin = min(
            max(0, margin),
            max(0, (recordingFrame.width - result.width) / 2)
        )
        let verticalMargin = min(
            max(0, margin),
            max(0, (recordingFrame.height - result.height) / 2)
        )
        result.origin.x = clampedOrigin(
            value: result.origin.x,
            lowerBound: recordingFrame.minX + horizontalMargin,
            upperBound: recordingFrame.maxX - result.width - horizontalMargin
        )
        result.origin.y = clampedOrigin(
            value: result.origin.y,
            lowerBound: recordingFrame.minY + verticalMargin,
            upperBound: recordingFrame.maxY - result.height - verticalMargin
        )
        return result
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
