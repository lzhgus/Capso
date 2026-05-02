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
}
