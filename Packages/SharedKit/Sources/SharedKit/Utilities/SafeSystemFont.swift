import AppKit
import CoreText

/// AppKit's system-font factories are audited `nonnull`, so Swift imports them
/// as non-optional `NSFont`. They can still hand back `nil` at runtime when the
/// font system fails to vend the requested UI font. Swift stores that `nil`
/// straight into a `[NSAttributedString.Key: Any]` literal, the literal bridges
/// to an `NSDictionary` holding a NULL value, and the first
/// `size(withAttributes:)` or `draw(at:withAttributes:)` aborts the process
/// inside CoreText:
///
///     *** -[__NSPlaceholderDictionary initWithObjects:forKeys:count:]:
///         attempt to insert nil object from objects[0]
///
/// A NULL `.font` is what triggers this — CoreText has to substitute a default
/// font, and rebuilding the attribute dictionary to inject it is what copies
/// the NULL. Other attributes such as `.foregroundColor` are not copied during
/// measurement and so never abort.
///
/// These wrappers make the `nil` observable and fall back through progressively
/// more basic fonts.
public extension NSFont {
    static func safeSystemFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        resolve(
            NSFont.systemFont(ofSize: size, weight: weight),
            NSFont.systemFont(ofSize: size),
            fallbackName: "Helvetica",
            size: size
        )
    }

    static func safeMonospacedSystemFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        resolve(
            NSFont.monospacedSystemFont(ofSize: size, weight: weight),
            NSFont.userFixedPitchFont(ofSize: size),
            fallbackName: "Menlo",
            size: size
        )
    }

    static func safeMonospacedDigitSystemFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        resolve(
            NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            NSFont.systemFont(ofSize: size),
            fallbackName: "Helvetica",
            size: size
        )
    }

    /// Wraps `menuFont(ofSize:)`. A size of 0 asks for the default menu font
    /// size, so the fallback chain resolves it to the standard menu size first.
    static func safeMenuFont(ofSize size: CGFloat) -> NSFont {
        let effective = size > 0 ? size : NSFont.systemFontSize(for: .regular)
        return resolve(
            NSFont.menuFont(ofSize: size),
            NSFont.systemFont(ofSize: effective),
            fallbackName: "Helvetica",
            size: effective
        )
    }

    private static func resolve(
        _ primary: @autoclosure () -> NSFont?,
        _ secondary: @autoclosure () -> NSFont?,
        fallbackName: String,
        size: CGFloat
    ) -> NSFont {
        if let font = validated(primary()) { return font }
        if let font = validated(secondary()) { return font }
        // CTFontCreateWithName substitutes a usable font when the requested name
        // is unavailable, so it never yields NULL.
        return unsafeBitCast(CTFontCreateWithName(fallbackName as CFString, size, nil), to: NSFont.self)
    }

    /// A null reference can reach here wearing a non-optional type, because the
    /// nullability audit on the AppKit factories is not enforced at runtime.
    /// Reinterpreting the bits is what makes it observable.
    private static func validated(_ font: NSFont?) -> NSFont? {
        guard let font else { return nil }
        return unsafeBitCast(font, to: NSFont?.self)
    }
}
