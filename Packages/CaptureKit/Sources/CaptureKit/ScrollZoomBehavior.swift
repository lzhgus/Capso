import CoreGraphics

public enum ScrollZoomBehavior {
    public static func scaleFactor(
        verticalDelta: CGFloat,
        horizontalDelta: CGFloat,
        hasPreciseDeltas: Bool
    ) -> CGFloat? {
        guard abs(verticalDelta) >= 0.5 else { return nil }
        guard abs(verticalDelta) >= abs(horizontalDelta) * 1.5 else { return nil }

        let clampedDelta = min(max(verticalDelta, -24), 24)
        let sensitivity: CGFloat = hasPreciseDeltas ? 0.012 : 0.045
        return exp(clampedDelta * sensitivity)
    }
}
