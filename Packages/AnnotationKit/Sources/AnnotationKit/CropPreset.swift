import Foundation
import CoreGraphics

public enum CropPreset: String, CaseIterable, Sendable, Hashable {
    case freeform
    case original
    case square
    case ratio4x3
    case ratio3x2
    case ratio16x9

    /// Localized label for menus. Strings live in the main app's
    /// `Localizable.xcstrings`; lookups fall back to the source key in
    /// test environments that don't have the bundle loaded.
    public var displayName: String {
        switch self {
        case .freeform: return String(localized: "Freeform")
        case .original: return String(localized: "Original Ratio")
        case .square: return String(localized: "1 : 1 (Square)")
        case .ratio4x3: return String(localized: "4 : 3")
        case .ratio3x2: return String(localized: "3 : 2")
        case .ratio16x9: return String(localized: "16 : 9")
        }
    }

    /// Aspect ratio (width / height) this preset constrains to, or nil for freeform.
    /// `original` evaluates against the current image size.
    public func ratio(imageSize: CGSize) -> CGFloat? {
        switch self {
        case .freeform: return nil
        case .original:
            guard imageSize.height > 0 else { return nil }
            return imageSize.width / imageSize.height
        case .square: return 1.0
        case .ratio4x3: return 4.0 / 3.0
        case .ratio3x2: return 3.0 / 2.0
        case .ratio16x9: return 16.0 / 9.0
        }
    }
}
