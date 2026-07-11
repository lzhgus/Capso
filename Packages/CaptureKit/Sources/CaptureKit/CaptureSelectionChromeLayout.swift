import CoreGraphics

public enum CaptureSelectionChromeLayout {
    public static let minimumEdgeHandleDimension: CGFloat = 80

    public static func visibleHandles(
        for selectionSize: CGSize,
        isFixedSize: Bool
    ) -> [CaptureSelectionResizeHandle] {
        guard !isFixedSize else { return [] }
        let corners: [CaptureSelectionResizeHandle] = [
            .topLeft, .topRight, .bottomRight, .bottomLeft,
        ]
        guard min(selectionSize.width, selectionSize.height) >= minimumEdgeHandleDimension else {
            return corners
        }
        return [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]
    }

    public static func dimensionText(for selectionSize: CGSize) -> String {
        "\(max(1, Int(selectionSize.width.rounded()))) × \(max(1, Int(selectionSize.height.rounded())))"
    }

    public static func dimensionHUDOrigin(
        selectionRect: CGRect,
        hudSize: CGSize,
        in bounds: CGRect,
        gap: CGFloat = 8,
        insideInset: CGFloat = 10
    ) -> CGPoint {
        let clampedX = min(max(selectionRect.minX, bounds.minX), bounds.maxX - hudSize.width)
        let aboveY = selectionRect.maxY + gap
        if aboveY + hudSize.height <= bounds.maxY {
            return CGPoint(x: clampedX, y: aboveY)
        }
        let belowY = selectionRect.minY - gap - hudSize.height
        if belowY >= bounds.minY {
            return CGPoint(x: clampedX, y: belowY)
        }
        return CGPoint(
            x: min(max(selectionRect.minX + insideInset, bounds.minX), bounds.maxX - hudSize.width),
            y: min(max(selectionRect.maxY - hudSize.height - insideInset, bounds.minY), bounds.maxY - hudSize.height)
        )
    }
}
