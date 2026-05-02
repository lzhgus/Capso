import CoreGraphics

public enum CaptureSelectionResizeHandle: Sendable, Equatable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

public enum CaptureSelectionHitTarget: Sendable, Equatable {
    case move
    case resize(CaptureSelectionResizeHandle)
}

public enum CaptureSelectionGeometry {
    public static func rect(
        from startPoint: CGPoint,
        to currentPoint: CGPoint,
        in bounds: CGRect,
        minSize: CGSize
    ) -> CGRect {
        let start = clamp(startPoint, to: bounds)
        let current = clamp(currentPoint, to: bounds)
        let minWidth = min(max(1, minSize.width), bounds.width)
        let minHeight = min(max(1, minSize.height), bounds.height)

        var minX = min(start.x, current.x)
        var maxX = max(start.x, current.x)
        var minY = min(start.y, current.y)
        var maxY = max(start.y, current.y)

        if maxX - minX < minWidth {
            if current.x >= start.x {
                maxX = min(bounds.maxX, start.x + minWidth)
                minX = max(bounds.minX, maxX - minWidth)
            } else {
                minX = max(bounds.minX, start.x - minWidth)
                maxX = min(bounds.maxX, minX + minWidth)
            }
        }

        if maxY - minY < minHeight {
            if current.y >= start.y {
                maxY = min(bounds.maxY, start.y + minHeight)
                minY = max(bounds.minY, maxY - minHeight)
            } else {
                minY = max(bounds.minY, start.y - minHeight)
                maxY = min(bounds.maxY, minY + minHeight)
            }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public static func rect(
        from startPoint: CGPoint,
        to currentPoint: CGPoint,
        in bounds: CGRect,
        minSize: CGSize,
        aspectRatio: CGFloat
    ) -> CGRect {
        guard aspectRatio > 0 else {
            return rect(
                from: startPoint,
                to: currentPoint,
                in: bounds,
                minSize: minSize
            )
        }

        let start = clamp(startPoint, to: bounds)
        let current = clamp(currentPoint, to: bounds)
        let horizontalDirection = direction(
            from: start.x,
            to: current.x,
            minimumBound: bounds.minX,
            maximumBound: bounds.maxX
        )
        let verticalDirection = direction(
            from: start.y,
            to: current.y,
            minimumBound: bounds.minY,
            maximumBound: bounds.maxY
        )

        return aspectRatioRect(
            anchoredAt: start,
            horizontalDirection: horizontalDirection,
            verticalDirection: verticalDirection,
            targetWidth: abs(current.x - start.x),
            targetHeight: abs(current.y - start.y),
            aspectRatio: aspectRatio,
            in: bounds,
            minSize: minSize
        )
    }

    public static func move(
        _ selectionRect: CGRect,
        by delta: CGVector,
        in bounds: CGRect
    ) -> CGRect {
        let rect = selectionRect.standardized
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = clamp(rect.minX + delta.dx, min: bounds.minX, max: bounds.maxX - width)
        let y = clamp(rect.minY + delta.dy, min: bounds.minY, max: bounds.maxY - height)

        return CGRect(x: x, y: y, width: width, height: height)
    }

    public static func fixedSize(
        _ size: CGSize,
        centeredAt center: CGPoint,
        in bounds: CGRect
    ) -> CGRect {
        let width = min(max(1, size.width), bounds.width)
        let height = min(max(1, size.height), bounds.height)
        let rect = CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )

        return move(rect, by: .zero, in: bounds)
    }

    public static func fit(
        _ selectionRect: CGRect,
        aspectRatio: CGFloat,
        in bounds: CGRect,
        minSize: CGSize
    ) -> CGRect {
        let rect = selectionRect.standardized
        guard aspectRatio > 0,
              rect.width > 0,
              rect.height > 0 else {
            return move(rect, by: .zero, in: bounds)
        }

        let minWidth = min(max(1, minSize.width), bounds.width)
        let minHeight = min(max(1, minSize.height), bounds.height)
        var width = rect.width
        var height = rect.height

        if width / height > aspectRatio {
            height = width / aspectRatio
        } else {
            width = height * aspectRatio
        }

        if width < minWidth {
            width = minWidth
            height = width / aspectRatio
        }
        if height < minHeight {
            height = minHeight
            width = height * aspectRatio
        }

        let maxWidth = bounds.width
        let maxHeight = bounds.height
        if width > maxWidth {
            width = maxWidth
            height = width / aspectRatio
        }
        if height > maxHeight {
            height = maxHeight
            width = height * aspectRatio
        }

        return fixedSize(
            CGSize(width: width, height: height),
            centeredAt: CGPoint(x: rect.midX, y: rect.midY),
            in: bounds
        )
    }

    public static func resize(
        _ selectionRect: CGRect,
        handle: CaptureSelectionResizeHandle,
        to point: CGPoint,
        in bounds: CGRect,
        minSize: CGSize
    ) -> CGRect {
        let rect = selectionRect.standardized
        let point = clamp(point, to: bounds)
        let minWidth = min(max(1, minSize.width), bounds.width)
        let minHeight = min(max(1, minSize.height), bounds.height)

        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch handle {
        case .topLeft:
            minX = clamp(point.x, min: bounds.minX, max: maxX - minWidth)
            maxY = clamp(point.y, min: minY + minHeight, max: bounds.maxY)
        case .top:
            maxY = clamp(point.y, min: minY + minHeight, max: bounds.maxY)
        case .topRight:
            maxX = clamp(point.x, min: minX + minWidth, max: bounds.maxX)
            maxY = clamp(point.y, min: minY + minHeight, max: bounds.maxY)
        case .right:
            maxX = clamp(point.x, min: minX + minWidth, max: bounds.maxX)
        case .bottomRight:
            maxX = clamp(point.x, min: minX + minWidth, max: bounds.maxX)
            minY = clamp(point.y, min: bounds.minY, max: maxY - minHeight)
        case .bottom:
            minY = clamp(point.y, min: bounds.minY, max: maxY - minHeight)
        case .bottomLeft:
            minX = clamp(point.x, min: bounds.minX, max: maxX - minWidth)
            minY = clamp(point.y, min: bounds.minY, max: maxY - minHeight)
        case .left:
            minX = clamp(point.x, min: bounds.minX, max: maxX - minWidth)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public static func resize(
        _ selectionRect: CGRect,
        handle: CaptureSelectionResizeHandle,
        to point: CGPoint,
        in bounds: CGRect,
        minSize: CGSize,
        aspectRatio: CGFloat
    ) -> CGRect {
        guard aspectRatio > 0 else {
            return resize(
                selectionRect,
                handle: handle,
                to: point,
                in: bounds,
                minSize: minSize
            )
        }

        let rect = selectionRect.standardized
        let point = clamp(point, to: bounds)

        switch handle {
        case .top:
            return verticalEdgeAspectRatioRect(
                rect,
                movingTop: true,
                targetY: point.y,
                aspectRatio: aspectRatio,
                in: bounds,
                minSize: minSize
            )
        case .bottom:
            return verticalEdgeAspectRatioRect(
                rect,
                movingTop: false,
                targetY: point.y,
                aspectRatio: aspectRatio,
                in: bounds,
                minSize: minSize
            )
        case .right:
            return horizontalEdgeAspectRatioRect(
                rect,
                movingRight: true,
                targetX: point.x,
                aspectRatio: aspectRatio,
                in: bounds,
                minSize: minSize
            )
        case .left:
            return horizontalEdgeAspectRatioRect(
                rect,
                movingRight: false,
                targetX: point.x,
                aspectRatio: aspectRatio,
                in: bounds,
                minSize: minSize
            )
        case .topRight:
            return aspectRatioRect(
                anchoredAt: CGPoint(x: rect.minX, y: rect.minY),
                horizontalDirection: 1,
                verticalDirection: 1,
                targetWidth: point.x - rect.minX,
                targetHeight: point.y - rect.minY,
                aspectRatio: aspectRatio,
                in: bounds,
                minSize: minSize
            )
        case .topLeft:
            return aspectRatioRect(
                anchoredAt: CGPoint(x: rect.maxX, y: rect.minY),
                horizontalDirection: -1,
                verticalDirection: 1,
                targetWidth: rect.maxX - point.x,
                targetHeight: point.y - rect.minY,
                aspectRatio: aspectRatio,
                in: bounds,
                minSize: minSize
            )
        case .bottomRight:
            return aspectRatioRect(
                anchoredAt: CGPoint(x: rect.minX, y: rect.maxY),
                horizontalDirection: 1,
                verticalDirection: -1,
                targetWidth: point.x - rect.minX,
                targetHeight: rect.maxY - point.y,
                aspectRatio: aspectRatio,
                in: bounds,
                minSize: minSize
            )
        case .bottomLeft:
            return aspectRatioRect(
                anchoredAt: CGPoint(x: rect.maxX, y: rect.maxY),
                horizontalDirection: -1,
                verticalDirection: -1,
                targetWidth: rect.maxX - point.x,
                targetHeight: rect.maxY - point.y,
                aspectRatio: aspectRatio,
                in: bounds,
                minSize: minSize
            )
        }
    }

    public static func hitTarget(
        at point: CGPoint,
        selectionRect: CGRect,
        hitSlop: CGFloat
    ) -> CaptureSelectionHitTarget? {
        let rect = selectionRect.standardized
        let slop = max(1, hitSlop)

        if isNear(point, CGPoint(x: rect.minX, y: rect.maxY), slop: slop) {
            return .resize(.topLeft)
        }
        if isNear(point, CGPoint(x: rect.maxX, y: rect.maxY), slop: slop) {
            return .resize(.topRight)
        }
        if isNear(point, CGPoint(x: rect.maxX, y: rect.minY), slop: slop) {
            return .resize(.bottomRight)
        }
        if isNear(point, CGPoint(x: rect.minX, y: rect.minY), slop: slop) {
            return .resize(.bottomLeft)
        }
        if abs(point.y - rect.maxY) <= slop, point.x >= rect.minX, point.x <= rect.maxX {
            return .resize(.top)
        }
        if abs(point.x - rect.maxX) <= slop, point.y >= rect.minY, point.y <= rect.maxY {
            return .resize(.right)
        }
        if abs(point.y - rect.minY) <= slop, point.x >= rect.minX, point.x <= rect.maxX {
            return .resize(.bottom)
        }
        if abs(point.x - rect.minX) <= slop, point.y >= rect.minY, point.y <= rect.maxY {
            return .resize(.left)
        }
        if rect.contains(point) {
            return .move
        }

        return nil
    }

    private static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: clamp(point.x, min: bounds.minX, max: bounds.maxX),
            y: clamp(point.y, min: bounds.minY, max: bounds.maxY)
        )
    }

    private static func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        guard minimum <= maximum else { return minimum }
        return Swift.min(Swift.max(value, minimum), maximum)
    }

    private static func isNear(_ point: CGPoint, _ target: CGPoint, slop: CGFloat) -> Bool {
        abs(point.x - target.x) <= slop && abs(point.y - target.y) <= slop
    }

    private static func direction(
        from start: CGFloat,
        to current: CGFloat,
        minimumBound: CGFloat,
        maximumBound: CGFloat
    ) -> CGFloat {
        if current > start {
            return 1
        }
        if current < start {
            return -1
        }
        if maximumBound - start >= start - minimumBound {
            return 1
        }
        return -1
    }

    private static func aspectRatioRect(
        anchoredAt anchor: CGPoint,
        horizontalDirection: CGFloat,
        verticalDirection: CGFloat,
        targetWidth: CGFloat,
        targetHeight: CGFloat,
        aspectRatio: CGFloat,
        in bounds: CGRect,
        minSize: CGSize
    ) -> CGRect {
        let maximumWidth = horizontalDirection >= 0
            ? bounds.maxX - anchor.x
            : anchor.x - bounds.minX
        let maximumHeight = verticalDirection >= 0
            ? bounds.maxY - anchor.y
            : anchor.y - bounds.minY
        let maximumRatioHeight = min(maximumHeight, maximumWidth / aspectRatio)
        let minimum = aspectRatioMinimumSize(aspectRatio: aspectRatio, minSize: minSize)
        let desiredHeight = max(0, targetHeight, targetWidth / aspectRatio)
        let height = constrainedDimension(
            desiredHeight,
            minimum: minimum.height,
            maximum: maximumRatioHeight
        )
        let width = height * aspectRatio
        let minX = horizontalDirection >= 0 ? anchor.x : anchor.x - width
        let minY = verticalDirection >= 0 ? anchor.y : anchor.y - height

        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private static func verticalEdgeAspectRatioRect(
        _ selectionRect: CGRect,
        movingTop: Bool,
        targetY: CGFloat,
        aspectRatio: CGFloat,
        in bounds: CGRect,
        minSize: CGSize
    ) -> CGRect {
        let rect = selectionRect.standardized
        let anchoredY = movingTop ? rect.minY : rect.maxY
        let centerX = rect.midX
        let maximumVerticalHeight = movingTop
            ? bounds.maxY - anchoredY
            : anchoredY - bounds.minY
        let maximumCenteredWidth = 2 * min(centerX - bounds.minX, bounds.maxX - centerX)
        let maximumHeight = min(maximumVerticalHeight, maximumCenteredWidth / aspectRatio)
        let desiredHeight = max(0, movingTop ? targetY - anchoredY : anchoredY - targetY)
        let minimum = aspectRatioMinimumSize(aspectRatio: aspectRatio, minSize: minSize)
        let height = constrainedDimension(
            desiredHeight,
            minimum: minimum.height,
            maximum: maximumHeight
        )
        let width = height * aspectRatio
        let x = centerX - width / 2
        let y = movingTop ? anchoredY : anchoredY - height

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func horizontalEdgeAspectRatioRect(
        _ selectionRect: CGRect,
        movingRight: Bool,
        targetX: CGFloat,
        aspectRatio: CGFloat,
        in bounds: CGRect,
        minSize: CGSize
    ) -> CGRect {
        let rect = selectionRect.standardized
        let anchoredX = movingRight ? rect.minX : rect.maxX
        let centerY = rect.midY
        let maximumHorizontalWidth = movingRight
            ? bounds.maxX - anchoredX
            : anchoredX - bounds.minX
        let maximumCenteredHeight = 2 * min(centerY - bounds.minY, bounds.maxY - centerY)
        let maximumWidth = min(maximumHorizontalWidth, maximumCenteredHeight * aspectRatio)
        let desiredWidth = max(0, movingRight ? targetX - anchoredX : anchoredX - targetX)
        let minimum = aspectRatioMinimumSize(aspectRatio: aspectRatio, minSize: minSize)
        let width = constrainedDimension(
            desiredWidth,
            minimum: minimum.width,
            maximum: maximumWidth
        )
        let height = width / aspectRatio
        let x = movingRight ? anchoredX : anchoredX - width
        let y = centerY - height / 2

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func aspectRatioMinimumSize(
        aspectRatio: CGFloat,
        minSize: CGSize
    ) -> CGSize {
        let minWidth = max(1, minSize.width)
        let minHeight = max(1, minSize.height)
        let width = max(minWidth, minHeight * aspectRatio)
        let height = max(minHeight, width / aspectRatio)

        return CGSize(width: height * aspectRatio, height: height)
    }

    private static func constrainedDimension(
        _ value: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        let maximum = max(0, maximum)
        guard maximum > 0 else { return 0 }

        let minimum = min(max(1, minimum), maximum)
        return clamp(value, min: minimum, max: maximum)
    }
}
