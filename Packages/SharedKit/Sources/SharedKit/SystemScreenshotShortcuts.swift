import Foundation

/// Whether macOS still claims ⇧⌘3, ⇧⌘4 and ⇧⌘5 for its own screenshot tool.
public enum SystemScreenshotShortcuts {
    /// Symbolic hot key IDs for "Save picture of screen" (⇧⌘3), "Save picture of
    /// selected area" (⇧⌘4) and "Screenshot and recording options" (⇧⌘5).
    static let hotKeyIDs = ["28", "30", "184"]

    /// `true` while any of them is on. A missing entry means macOS still uses its default, which is on.
    public static func areEnabled(in symbolicHotKeys: [String: Any]?) -> Bool {
        hotKeyIDs.contains { id in
            (symbolicHotKeys?[id] as? [String: Any])?["enabled"] as? Bool ?? true
        }
    }

    public static var areEnabled: Bool {
        let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys")
        return areEnabled(in: domain?["AppleSymbolicHotKeys"] as? [String: Any])
    }

    /// Opens the Keyboard Shortcuts area of System Settings.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
}
