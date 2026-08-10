import CoreGraphics

/// Placement for the floating controls/preview shown during scrolling capture.
///
/// Coordinates are AppKit bottom-left. Bounds must be the screen's `visibleFrame`
/// so Dock and menu bar never cover the chrome.
public enum ScrollCaptureOverlayPlacement {
    public static let defaultControlsSize = CGSize(width: 300, height: 52)
    public static let defaultControlsGap: CGFloat = 10
    public static let defaultMargin: CGFloat = 8
    public static let defaultPreviewWidth: CGFloat = 180
    public static let defaultPreviewGap: CGFloat = 12
    public static let defaultMaxPreviewHeight: CGFloat = 400

    /// Prefer below the selection, then above, then inside the visible area.
    public static func controlsFrame(
        selectionRect: CGRect,
        visibleFrame: CGRect,
        controlsSize: CGSize = defaultControlsSize,
        gap: CGFloat = defaultControlsGap,
        margin: CGFloat = defaultMargin
    ) -> CGRect {
        let selection = selectionRect.standardized
        let visible = visibleFrame.standardized
        let width = max(0, min(controlsSize.width, max(0, visible.width - margin * 2)))
        let height = max(0, min(controlsSize.height, max(0, visible.height - margin * 2)))

        let belowY = selection.minY - height - gap
        let aboveY = selection.maxY + gap

        let y: CGFloat
        if belowY >= visible.minY + margin {
            y = belowY
        } else if aboveY + height <= visible.maxY - margin {
            y = aboveY
        } else {
            y = clampedOrigin(
                value: selection.minY + margin,
                lowerBound: visible.minY + margin,
                upperBound: visible.maxY - height - margin
            )
        }

        let x = clampedOrigin(
            value: selection.midX - width / 2,
            lowerBound: visible.minX + margin,
            upperBound: visible.maxX - width - margin
        )

        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Prefer the left of the selection; fall back to the right. Returns `nil`
    /// when neither side fits inside `visibleFrame`.
    public static func previewFrame(
        selectionRect: CGRect,
        visibleFrame: CGRect,
        previewWidth: CGFloat = defaultPreviewWidth,
        maxPreviewHeight: CGFloat = defaultMaxPreviewHeight,
        gap: CGFloat = defaultPreviewGap,
        margin: CGFloat = defaultMargin
    ) -> CGRect? {
        let selection = selectionRect.standardized
        let visible = visibleFrame.standardized
        let width = max(0, min(previewWidth, max(0, visible.width - margin * 2)))
        guard width > 0 else { return nil }

        let height = max(
            0,
            min(min(selection.height, maxPreviewHeight), max(0, visible.height - margin * 2))
        )
        guard height > 0 else { return nil }

        let leftX = selection.minX - width - gap
        let rightX = selection.maxX + gap
        let x: CGFloat?
        if leftX >= visible.minX + margin {
            x = leftX
        } else if rightX + width <= visible.maxX - margin {
            x = rightX
        } else {
            x = nil
        }
        guard let x else { return nil }

        let y = clampedOrigin(
            value: selection.midY - height / 2,
            lowerBound: visible.minY + margin,
            upperBound: visible.maxY - height - margin
        )

        return CGRect(x: x, y: y, width: width, height: height)
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
