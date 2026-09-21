import AppKit
import EditorKit
import SwiftUI

/// Background style for the Beautify background surrounding the screenshot.
enum BeautifyBackgroundStyle: String, CaseIterable, Identifiable, Hashable {
    /// Flat color fill (the original behaviour).
    case solid
    /// Two-stop diagonal gradient from a curated preset.
    case gradient
    /// A heavily blurred, saturation-boosted copy of the screenshot
    /// used as the backdrop — extends the image's own colours into the
    /// padding area for a "liquid glass" look.
    case liquidGlass

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .solid: "Solid"
        case .gradient: "Gradient"
        case .liquidGlass: "Liquid Glass"
        }
    }
}

/// Curated two-stop gradients for the Beautify background. Built from the
/// recording editor's warm, desaturated palette (`EditorKit.CodableColor`)
/// so screenshots and recordings share one look. Every preset runs from the
/// top-leading to the bottom-trailing corner.
enum BeautifyGradientPreset: String, CaseIterable, Identifiable, Hashable {
    case graphite
    case dusk
    case slate
    case sand
    case sage
    case clay

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .graphite: "Graphite"
        case .dusk: "Dusk"
        case .slate: "Slate"
        case .sand: "Sand"
        case .sage: "Sage"
        case .clay: "Clay"
        }
    }

    var from: NSColor {
        switch self {
        case .graphite: NSColor(CodableColor.ink)
        case .dusk: NSColor(CodableColor.dusk)
        case .slate: NSColor(CodableColor.stone)
        case .sand: NSColor(CodableColor.mist)
        case .sage: NSColor(CodableColor.sage)
        case .clay: NSColor(CodableColor.clay)
        }
    }

    var to: NSColor {
        switch self {
        case .graphite: NSColor(CodableColor.stone)
        case .dusk: NSColor(CodableColor.ink)
        case .slate: NSColor(CodableColor.dusk)
        case .sand: NSColor(CodableColor.sand)
        case .sage: NSColor(CodableColor.mist)
        case .clay: NSColor(CodableColor.sand)
        }
    }
}

private extension NSColor {
    convenience init(_ color: CodableColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

struct BeautifySettings {
    var isEnabled = false
    var backgroundStyle: BeautifyBackgroundStyle = .solid
    var backgroundColor: Color = .white
    var gradientPreset: BeautifyGradientPreset = .graphite
    var padding: CGFloat = 40
    var cornerRadius: CGFloat = 12
    var shadowEnabled = true
    var shadowRadius: CGFloat = 20

    var clampedPadding: CGFloat { max(0, padding) }
    var clampedCornerRadius: CGFloat { max(0, cornerRadius) }
    var clampedShadowRadius: CGFloat { shadowEnabled ? max(0, shadowRadius) : 0 }
    var shadowInset: CGFloat { shadowEnabled ? clampedShadowRadius + 6 : 0 }
    var outerInset: CGFloat { clampedPadding + shadowInset }
}
