import CoreGraphics

public enum CaptureChromeDensity: Sendable {
    case mini
    case compact
    case regular
}

public enum CaptureChromeLayout {
    public static let startsWithCompactSideRail = true

    public static func annotationDensity(for availableWidth: CGFloat) -> CaptureChromeDensity {
        if availableWidth < 480 {
            return .mini
        }
        if availableWidth < 840 {
            return .compact
        }
        return .regular
    }
}
