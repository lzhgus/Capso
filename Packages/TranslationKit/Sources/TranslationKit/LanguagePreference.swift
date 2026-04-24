// Packages/TranslationKit/Sources/TranslationKit/LanguagePreference.swift
import Foundation

/// Utilities around the target language for translation.
public enum LanguagePreference {
    /// Languages Apple's Translation framework supports on macOS 15.
    /// Source: developer.apple.com/documentation/translation — keep in sync.
    /// Note: tags here are what Apple's framework accepts — `pt-BR` (not `pt`),
    /// `zh-Hans` / `zh-Hant` (not bare `zh`).
    private static let supportedLanguageCodes: Set<String> = [
        "ar", "de", "en", "es", "fr", "hi", "id", "it", "ja", "ko",
        "nl", "pl", "pt-BR", "ru", "tr", "uk",
        "zh-Hans", "zh-Hant"
    ]

    /// Regions where Chinese defaults to Traditional script even without an
    /// explicit `script` subtag on the Locale.
    private static let traditionalChineseRegions: Set<String> = ["TW", "HK", "MO"]

    /// Returns a reasonable default target given a locale.
    /// Prefers the locale's own language when supported; otherwise falls back to "en".
    public static func defaultTarget(for locale: Locale = .current) -> String {
        guard let code = locale.language.languageCode?.identifier else { return "en" }

        // Chinese: resolve Simplified vs Traditional from script or region.
        if code == "zh" {
            let script = locale.language.script?.identifier
            let region = locale.region?.identifier
            let isTraditional = script == "Hant"
                || (script == nil && region.map(traditionalChineseRegions.contains) == true)
            let bcp = isTraditional ? "zh-Hant" : "zh-Hans"
            return isSupported(bcp) ? bcp : "en"
        }

        // Portuguese: Apple ships pt-BR only.
        if code == "pt" {
            return isSupported("pt-BR") ? "pt-BR" : "en"
        }

        return isSupported(code) ? code : "en"
    }

    /// Whether Apple's framework accepts this BCP-47 code as a target/source.
    public static func isSupported(_ code: String) -> Bool {
        supportedLanguageCodes.contains(code)
    }
}
