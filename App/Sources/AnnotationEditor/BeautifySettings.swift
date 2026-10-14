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

/// Curated gradients for the Beautify background.
///
/// Two families: `vivid` presets are hand-tuned, saturated gradients for
/// screenshots that should pop when shared; `muted` presets reuse the
/// recording editor's warm, desaturated palette (`EditorKit.CodableColor`).
/// Stops run in gradient direction; `angle` uses the CSS convention
/// (degrees, 0 = bottom-to-top, 90 = left-to-right, 180 = top-to-bottom,
/// 135 = top-leading to bottom-trailing).
enum BeautifyGradientPreset: String, CaseIterable, Identifiable, Hashable {
    // Vivid
    case sunset
    case peach
    case rose
    case amber
    case ocean
    case aurora
    case forest
    case berry
    case midnight
    // Muted
    case graphite
    case dusk
    case slate
    case sand
    case sage
    case clay

    static let vivid: [BeautifyGradientPreset] = [
        .sunset, .peach, .rose, .amber, .ocean, .aurora, .forest, .berry, .midnight,
    ]
    static let muted: [BeautifyGradientPreset] = [
        .graphite, .dusk, .slate, .sand, .sage, .clay,
    ]

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .sunset: "Sunset"
        case .peach: "Peach"
        case .rose: "Rose"
        case .amber: "Amber"
        case .ocean: "Ocean"
        case .aurora: "Aurora"
        case .forest: "Forest"
        case .berry: "Berry"
        case .midnight: "Midnight"
        case .graphite: "Graphite"
        case .dusk: "Dusk"
        case .slate: "Slate"
        case .sand: "Sand"
        case .sage: "Sage"
        case .clay: "Clay"
        }
    }

    /// Gradient angle in degrees (CSS convention). Diagonal for everything
    /// but the vertical, sky-like presets.
    var angle: Double {
        switch self {
        case .sunset, .midnight: 180
        default: 135
        }
    }

    var stops: [NSColor] {
        switch self {
        case .sunset: [NSColor(hex: 0xFFB66E), NSColor(hex: 0xFF6B8B), NSColor(hex: 0xC6426E)]
        case .peach: [NSColor(hex: 0xFFE0B5), NSColor(hex: 0xFF9A8B)]
        case .rose: [NSColor(hex: 0xFBD3E9), NSColor(hex: 0xF0699B)]
        case .amber: [NSColor(hex: 0xFFE68A), NSColor(hex: 0xF59E0B)]
        case .ocean: [NSColor(hex: 0x36CFC9), NSColor(hex: 0x1D4ED8)]
        case .aurora: [NSColor(hex: 0x6EE7B7), NSColor(hex: 0x3B82F6), NSColor(hex: 0x7C3AED)]
        case .forest: [NSColor(hex: 0x34D399), NSColor(hex: 0x115E59)]
        case .berry: [NSColor(hex: 0xF472B6), NSColor(hex: 0x6D28D9)]
        case .midnight: [NSColor(hex: 0x1E3A5F), NSColor(hex: 0x0B1220)]
        case .graphite: [NSColor(CodableColor.ink), NSColor(CodableColor.stone)]
        case .dusk: [NSColor(CodableColor.dusk), NSColor(CodableColor.ink)]
        case .slate: [NSColor(CodableColor.stone), NSColor(CodableColor.dusk)]
        case .sand: [NSColor(CodableColor.mist), NSColor(CodableColor.sand)]
        case .sage: [NSColor(CodableColor.sage), NSColor(CodableColor.mist)]
        case .clay: [NSColor(CodableColor.clay), NSColor(CodableColor.sand)]
        }
    }
}

/// Start/end of a linear gradient in unit coordinates with a top-left
/// origin (SwiftUI's `UnitPoint` space). Shared by the editor preview and
/// `BeautifyRenderer` so both draw the same thing.
///
/// `angle` is in degrees using the CSS convention: 0 = bottom-to-top,
/// 90 = left-to-right, 180 = top-to-bottom. The half-length is stretched so
/// that diagonal angles reach the corners.
enum BeautifyGradientGeometry {
    static func unitPoints(angle: Double) -> (start: UnitPoint, end: UnitPoint) {
        let radians = angle * .pi / 180
        let dx = sin(radians)
        let dy = -cos(radians)
        let halfLength = 0.5 * (abs(dx) + abs(dy))
        return (
            UnitPoint(x: 0.5 - dx * halfLength, y: 0.5 - dy * halfLength),
            UnitPoint(x: 0.5 + dx * halfLength, y: 0.5 + dy * halfLength)
        )
    }
}

private extension NSColor {
    convenience init(_ color: CodableColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct BeautifySettings {
    var isEnabled = false
    var backgroundStyle: BeautifyBackgroundStyle = .solid
    var backgroundColor: Color = .white
    /// `nil` means the custom start/end colours below are in use.
    var gradientPreset: BeautifyGradientPreset? = .sunset
    var gradientCustomStart: Color = Color(nsColor: NSColor(srgbRed: 0.36, green: 0.55, blue: 0.98, alpha: 1))
    var gradientCustomEnd: Color = Color(nsColor: NSColor(srgbRed: 0.93, green: 0.42, blue: 0.62, alpha: 1))
    /// Degrees, CSS convention (180 = top-to-bottom). Reset when a preset is picked.
    var gradientAngle: CGFloat = 180
    var padding: CGFloat = 40
    var cornerRadius: CGFloat = 12
    var shadowEnabled = true
    var shadowRadius: CGFloat = 20

    var clampedPadding: CGFloat { max(0, padding) }
    var clampedCornerRadius: CGFloat { max(0, cornerRadius) }
    var clampedShadowRadius: CGFloat { shadowEnabled ? max(0, shadowRadius) : 0 }
    var shadowInset: CGFloat { shadowEnabled ? clampedShadowRadius + 6 : 0 }
    var outerInset: CGFloat { clampedPadding + shadowInset }

    /// Colour stops of the active gradient (preset or custom), in order.
    var gradientStops: [NSColor] {
        if let gradientPreset {
            return gradientPreset.stops
        }
        return [NSColor(gradientCustomStart), NSColor(gradientCustomEnd)]
    }

    mutating func selectGradientPreset(_ preset: BeautifyGradientPreset) {
        gradientPreset = preset
        gradientAngle = CGFloat(preset.angle)
    }
}
