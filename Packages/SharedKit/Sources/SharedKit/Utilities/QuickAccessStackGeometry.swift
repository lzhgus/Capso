import CoreGraphics

public enum QuickAccessStackGeometry {
    private static let edgeInset: CGFloat = 16
    private static let stackSpacing: CGFloat = 12

    public static func frame(
        position: QuickAccessPosition,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        windowSize: CGSize,
        stackIndex: Int,
        stackCount: Int
    ) -> CGRect {
        precondition(stackCount > 0, "A Quick Access stack must contain at least one preview")
        precondition(stackIndex >= 0 && stackIndex < stackCount, "Stack index must be within the stack")

        let stackStep = windowSize.height + stackSpacing
        let stackHeight = CGFloat(stackCount) * windowSize.height
            + CGFloat(stackCount - 1) * stackSpacing
        let centeredStackMinY = visibleFrame.midY - stackHeight / 2 - 48
        let boundedCenteredStackMinY = min(
            max(centeredStackMinY, visibleFrame.minY + edgeInset),
            visibleFrame.maxY - edgeInset - stackHeight
        )

        let origin: CGPoint = switch position {
        case .bottomLeft:
            CGPoint(
                x: visibleFrame.minX + edgeInset,
                y: visibleFrame.minY + edgeInset + CGFloat(stackIndex) * stackStep
            )
        case .centerScreen:
            CGPoint(
                x: visibleFrame.midX - windowSize.width / 2,
                y: boundedCenteredStackMinY + CGFloat(stackIndex) * stackStep
            )
        case .bottomRight:
            CGPoint(
                x: visibleFrame.maxX - windowSize.width - edgeInset,
                y: visibleFrame.minY + edgeInset + CGFloat(stackIndex) * stackStep
            )
        }

        return CGRect(origin: origin, size: windowSize)
    }
}
