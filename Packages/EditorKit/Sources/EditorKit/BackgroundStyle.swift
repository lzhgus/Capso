// Packages/EditorKit/Sources/EditorKit/BackgroundStyle.swift

import Foundation

/// Background fill type for the area behind the video frame.
public enum BackgroundColorType: String, Codable, Sendable {
    case solid
    case gradient
    /// Blurred, saturation-boosted copy of the video frame as backdrop.
    case liquidGlass
}

/// A Codable, platform-agnostic color representation using normalized RGBA components.
public struct CodableColor: Codable, Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = CodableColor(red: 1.0, green: 1.0, blue: 1.0)
    public static let black = CodableColor(red: 0.0, green: 0.0, blue: 0.0)
    public static let darkGray = CodableColor(red: 0.2, green: 0.2, blue: 0.2)

    // MARK: - Capso Solid Background Palette
    //
    // A warm, desaturated, tinted-neutral palette — never pure #000/#fff,
    // never the AI-slop cyan/purple gradient palette, never full-saturation
    // rainbow swatches. Values are hand-tuned to:
    //   • frame recorded video without fighting it for attention
    //   • read as "warm, restrained, crafted" (see .impeccable.md)
    //   • stay harmonious with macOS's stock `Color.accentColor` as the
    //     selection indicator
    //
    // Hex comments are informative — canonical source is the RGB triple.
    public static let ink   = CodableColor(red: 0.102, green: 0.094, blue: 0.078) // #1A1814 — warm deep black
    public static let stone = CodableColor(red: 0.239, green: 0.216, blue: 0.192) // #3D3731 — warm charcoal
    public static let mist  = CodableColor(red: 0.910, green: 0.898, blue: 0.875) // #E8E5DF — warm off-white
    public static let sand  = CodableColor(red: 0.827, green: 0.796, blue: 0.745) // #D3CBBE — cappuccino
    public static let dusk  = CodableColor(red: 0.290, green: 0.341, blue: 0.459) // #4A5775 — muted indigo
    public static let sage  = CodableColor(red: 0.608, green: 0.659, blue: 0.569) // #9BA891 — muted green
    public static let clay  = CodableColor(red: 0.710, green: 0.514, blue: 0.431) // #B5836E — muted terracotta
}

/// Describes the decorative background rendered behind the video in the editor output.
public struct BackgroundStyle: Codable, Sendable, Equatable {
    /// Maximum corner radius exposed to the slider, expressed in SOURCE
    /// (video) pixels — the same space the export compositor works in
    /// (`FrameCompositor.applyRoundedCorners` multiplies by canvas/source
    /// scale). The preview mirrors this by multiplying by preview/source
    /// scale before setting `CALayer.cornerRadius`, so the slider produces
    /// the same visible corner on screen as appears in the exported video.
    ///
    /// Earlier iterations set this value directly as VIEW points, which
    /// meant a slider max of 32 produced a tiny corner on a 1920×1080
    /// preview (~3% of the visible short dimension). 120 source-pixels on
    /// a 1920-wide video is ~6% — matches Annotate's chunky-rounded-card
    /// look that the user is comparing against.
    public static let maxCornerRadius: Double = 120.0

    /// When `false`, the video is rendered without any background decoration.
    public var enabled: Bool
    public var colorType: BackgroundColorType
    public var solidColor: CodableColor
    public var gradientFrom: CodableColor
    public var gradientTo: CodableColor
    /// Angle of the gradient in degrees (0 = top-to-bottom).
    public var gradientAngle: Double
    /// Padding around the video content, in points (0–80).
    public var padding: Double
    /// Corner radius applied to the video frame.
    public var cornerRadius: Double
    public var shadowEnabled: Bool
    /// Blur radius of the drop shadow (0–30).
    public var shadowRadius: Double
    /// Opacity of the drop shadow (0–1).
    public var shadowOpacity: Double

    public init(
        enabled: Bool = false,
        colorType: BackgroundColorType = .solid,
        solidColor: CodableColor = .darkGray,
        gradientFrom: CodableColor = .black,
        gradientTo: CodableColor = .darkGray,
        gradientAngle: Double = 135.0,
        padding: Double = 20.0,
        cornerRadius: Double = 12.0,
        shadowEnabled: Bool = true,
        shadowRadius: Double = 15.0,
        shadowOpacity: Double = 0.5
    ) {
        self.enabled = enabled
        self.colorType = colorType
        self.solidColor = solidColor
        self.gradientFrom = gradientFrom
        self.gradientTo = gradientTo
        self.gradientAngle = gradientAngle
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowEnabled = shadowEnabled
        self.shadowRadius = shadowRadius
        self.shadowOpacity = shadowOpacity
    }

    public func clampedCornerRadius(for frameSize: CGSize) -> Double {
        let geometricCap = min(frameSize.width, frameSize.height) / 2
        return min(max(0, cornerRadius), min(Self.maxCornerRadius, geometricCap))
    }

    /// Default background style with sensible initial values.
    public static let `default` = BackgroundStyle()
}
