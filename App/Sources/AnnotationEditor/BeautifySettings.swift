import AppKit
import SharedKit
import SwiftUI

/// Background style for the Beautify background surrounding the screenshot.
enum BeautifyBackgroundStyle: String, CaseIterable, Identifiable, Hashable {
    /// Flat color fill (the original behaviour).
    case solid
    /// A heavily blurred, saturation-boosted copy of the screenshot
    /// used as the backdrop — extends the image's own colours into the
    /// padding area for a "liquid glass" look.
    case liquidGlass
    /// Transparent, for rounded corners and shadow alone.
    case none

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .solid: "Solid"
        case .liquidGlass: "Liquid Glass"
        case .none: "None"
        }
    }
}

struct BeautifySettings {
    var isEnabled = false
    var backgroundStyle: BeautifyBackgroundStyle = .solid
    var backgroundColor: Color = .white
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

extension BeautifySettings {
    private struct Style: Codable {
        var backgroundStyle: String
        var backgroundColor: [CGFloat]
        var padding: CGFloat
        var cornerRadius: CGFloat
        var shadowEnabled: Bool
        var shadowRadius: CGFloat
    }

    /// The last style set in the editor, with Beautify itself left off.
    static func saved(settings: AppSettings = AppSettings()) -> BeautifySettings {
        var result = BeautifySettings()
        guard let data = settings.beautifyStyle,
              let style = try? JSONDecoder().decode(Style.self, from: data) else { return result }
        result.backgroundStyle = BeautifyBackgroundStyle(rawValue: style.backgroundStyle) ?? .solid
        if style.backgroundColor.count == 4 {
            let c = style.backgroundColor
            result.backgroundColor = Color(nsColor: NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3]))
        }
        result.padding = style.padding
        result.cornerRadius = style.cornerRadius
        result.shadowEnabled = style.shadowEnabled
        result.shadowRadius = style.shadowRadius
        return result
    }

    func saveStyle(settings: AppSettings = AppSettings()) {
        let color = NSColor(backgroundColor).usingColorSpace(.sRGB) ?? .white
        let style = Style(
            backgroundStyle: backgroundStyle.rawValue,
            backgroundColor: [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent],
            padding: padding,
            cornerRadius: cornerRadius,
            shadowEnabled: shadowEnabled,
            shadowRadius: shadowRadius
        )
        settings.beautifyStyle = try? JSONEncoder().encode(style)
    }
}
