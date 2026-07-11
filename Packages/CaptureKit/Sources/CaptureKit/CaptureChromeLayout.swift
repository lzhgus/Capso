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
        if availableWidth < 1_000 {
            return .compact
        }
        return .regular
    }

    public static func annotationToolbarHeight(
        density: CaptureChromeDensity,
        showsOverflow: Bool
    ) -> CGFloat {
        switch density {
        case .mini, .compact:
            return showsOverflow ? 102 : 58
        case .regular:
            return 58
        }
    }

    public static func showsInlineTextEffects(for density: CaptureChromeDensity) -> Bool {
        density == .regular
    }
}
