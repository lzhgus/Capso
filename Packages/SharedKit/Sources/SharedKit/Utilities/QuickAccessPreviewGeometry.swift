import CoreGraphics

public enum QuickAccessPreviewGeometry {
    public static func contentSize(
        imagePixelSize: CGSize,
        availableSize: CGSize,
        maxViewportFraction: CGFloat
    ) -> CGSize {
        guard imagePixelSize.width > 0,
              imagePixelSize.height > 0,
              availableSize.width > 0,
              availableSize.height > 0,
              maxViewportFraction > 0 else {
            return .zero
        }

        let maxWidth = availableSize.width * maxViewportFraction
        let maxHeight = availableSize.height * maxViewportFraction
        let scale = min(maxWidth / imagePixelSize.width, maxHeight / imagePixelSize.height)

        return CGSize(
            width: (imagePixelSize.width * scale).rounded(.down),
            height: (imagePixelSize.height * scale).rounded(.down)
        )
    }
}
