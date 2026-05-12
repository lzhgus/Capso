import CoreGraphics

public enum TextResizeHandle: Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

public enum TextResizeGeometry {
    public static func rect(
        originalBounds: CGRect,
        handle: TextResizeHandle,
        dragDelta: CGSize,
        minSize: CGSize
    ) -> CGRect {
        var rect = targetRect(
            originalBounds: originalBounds,
            handle: handle,
            dragDelta: dragDelta
        )

        switch handle {
        case .topLeft, .bottomLeft:
            let maxX = originalBounds.maxX
            rect.origin.x = min(rect.origin.x, maxX - minSize.width)
            rect.size.width = maxX - rect.origin.x
        case .topRight, .bottomRight:
            rect.size.width = max(minSize.width, rect.width)
        }

        switch handle {
        case .topLeft, .topRight:
            let maxY = originalBounds.maxY
            rect.origin.y = min(rect.origin.y, maxY - minSize.height)
            rect.size.height = maxY - rect.origin.y
        case .bottomLeft, .bottomRight:
            rect.size.height = max(minSize.height, rect.height)
        }

        return rect
    }

    public static func fontSize(
        originalBounds: CGRect,
        originalFontSize: CGFloat,
        handle: TextResizeHandle,
        dragDelta: CGSize,
        minFontSize: CGFloat = 6
    ) -> CGFloat {
        guard originalBounds.width > 0, originalBounds.height > 0 else {
            return max(minFontSize, originalFontSize)
        }

        let target = targetRect(
            originalBounds: originalBounds,
            handle: handle,
            dragDelta: dragDelta
        )
        let scaleX = max(10, target.width) / originalBounds.width
        let scaleY = max(10, target.height) / originalBounds.height
        return max(minFontSize, originalFontSize * max(scaleX, scaleY))
    }

    public static func origin(
        originalBounds: CGRect,
        resizedSize: CGSize,
        handle: TextResizeHandle
    ) -> CGPoint {
        switch handle {
        case .topLeft:
            CGPoint(
                x: originalBounds.maxX - resizedSize.width,
                y: originalBounds.maxY - resizedSize.height
            )
        case .topRight:
            CGPoint(
                x: originalBounds.minX,
                y: originalBounds.maxY - resizedSize.height
            )
        case .bottomLeft:
            CGPoint(
                x: originalBounds.maxX - resizedSize.width,
                y: originalBounds.minY
            )
        case .bottomRight:
            originalBounds.origin
        }
    }

    private static func targetRect(
        originalBounds: CGRect,
        handle: TextResizeHandle,
        dragDelta: CGSize
    ) -> CGRect {
        var rect = originalBounds
        switch handle {
        case .topLeft:
            rect.origin.x = originalBounds.minX + dragDelta.width
            rect.origin.y = originalBounds.minY + dragDelta.height
            rect.size.width = originalBounds.width - dragDelta.width
            rect.size.height = originalBounds.height - dragDelta.height
        case .topRight:
            rect.origin.y = originalBounds.minY + dragDelta.height
            rect.size.width = originalBounds.width + dragDelta.width
            rect.size.height = originalBounds.height - dragDelta.height
        case .bottomLeft:
            rect.origin.x = originalBounds.minX + dragDelta.width
            rect.size.width = originalBounds.width - dragDelta.width
            rect.size.height = originalBounds.height + dragDelta.height
        case .bottomRight:
            rect.size.width = originalBounds.width + dragDelta.width
            rect.size.height = originalBounds.height + dragDelta.height
        }
        return rect
    }
}
