import CoreGraphics

public enum CaptureDisplayGeometry {
    public static func screenLocalRect(
        fromTopLeftCaptureRect captureRect: CGRect,
        screenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: captureRect.origin.x,
            y: screenHeight - captureRect.origin.y - captureRect.height,
            width: captureRect.width,
            height: captureRect.height
        )
    }

    public static func displayScale(imageSize: CGSize, screenRect: CGRect) -> CGFloat? {
        guard imageSize.width > 0,
              imageSize.height > 0,
              screenRect.width > 0,
              screenRect.height > 0 else {
            return nil
        }

        return min(screenRect.width / imageSize.width, screenRect.height / imageSize.height)
    }

    public static func presetBadgeY(
        viewHeight: CGFloat,
        badgeHeight: CGFloat,
        safeAreaTopInset: CGFloat
    ) -> CGFloat {
        let topMargin: CGFloat = safeAreaTopInset > 0 ? 64 : 20
        return viewHeight - badgeHeight - safeAreaTopInset - topMargin
    }

    public static func frozenImageCropRect(
        screenLocalRect: CGRect,
        screenSize: CGSize,
        imageSize: CGSize
    ) -> CGRect {
        guard screenLocalRect.width > 0,
              screenLocalRect.height > 0,
              screenSize.width > 0,
              screenSize.height > 0,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return .null
        }

        let scaleX = imageSize.width / screenSize.width
        let scaleY = imageSize.height / screenSize.height

        return CGRect(
            x: screenLocalRect.origin.x * scaleX,
            y: (screenSize.height - screenLocalRect.origin.y - screenLocalRect.height) * scaleY,
            width: screenLocalRect.width * scaleX,
            height: screenLocalRect.height * scaleY
        ).integral
    }

    public static func displayLocalRect(
        fromGlobalTopLeftRect globalRect: CGRect,
        displayBounds: CGRect
    ) -> CGRect {
        guard globalRect.width > 0,
              globalRect.height > 0,
              displayBounds.width > 0,
              displayBounds.height > 0 else {
            return .null
        }

        let localRect = CGRect(
            x: globalRect.origin.x - displayBounds.origin.x,
            y: globalRect.origin.y - displayBounds.origin.y,
            width: globalRect.width,
            height: globalRect.height
        )
        let localBounds = CGRect(origin: .zero, size: displayBounds.size)
        let visibleRect = localRect.intersection(localBounds)
        return visibleRect.isNull || visibleRect.isEmpty ? .null : visibleRect
    }
}
