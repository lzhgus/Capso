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
}
