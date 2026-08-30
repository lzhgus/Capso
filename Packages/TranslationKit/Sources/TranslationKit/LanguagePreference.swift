// Packages/TranslationKit/Sources/TranslationKit/LanguagePreference.swift
import Foundation
import Translation

/// Utilities around the target language for translation.
public enum LanguagePreference {
    /// Canonical fallback target languages supported on macOS 15.
    /// Used when `LanguageAvailability` returns empty or before async load completes.
    public static let fallbackLanguageCodes: [String] = [
        "ar", "de", "en", "es", "fr",
        "hi", "id", "it", "ja", "ko",
        "nl", "pl", "pt-BR", "ru", "th",
        "tr", "uk", "vi", "zh-Hans", "zh-Hant"
    ]

    /// Languages Apple's Translation framework documented as core supported.
    /// Note: tags here are what Apple's framework accepts — `pt-BR` (not `pt`),
    /// `zh-Hans` / `zh-Hant` (not bare `zh`).
    public static let supportedLanguageCodes: Set<String> = [
        "ar", "de", "en", "es", "fr",
        "hi", "id", "it", "ja", "ko",
        "nl", "pl", "pt-BR", "ru",
        "tr", "uk", "zh-Hans", "zh-Hant"
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

    /// Fetches the authoritative list of target language BCP-47 codes from
    /// Apple's `LanguageAvailability`. Falls back to the passed list if the
    /// framework returns an empty set.
    ///
    /// `supportedLanguages` returns regional variants (e.g. en-US, en-GB, zh-Hans-CN,
    /// zh-Hant-TW). We deduplicate to unique canonical codes: language-only for most
    /// languages, language-script for Chinese (which has two distinct scripts).
    public static func loadSupportedLanguageCodes(fallback: [String] = fallbackLanguageCodes) async -> [String] {
        let langs: [Locale.Language] = await Task.detached {
            let availability = LanguageAvailability()
            return await availability.supportedLanguages
        }.value
        if langs.isEmpty { return fallback }

        var seen = Set<String>()
        var result: [String] = []
        for lang in langs {
            guard let langCode = lang.languageCode?.identifier else { continue }
            let canonical: String
            if langCode == "zh", let script = lang.script?.identifier {
                canonical = "\(langCode)-\(script)"
            } else if langCode == "pt", let region = lang.region?.identifier, region == "BR" {
                canonical = "pt-BR"
            } else {
                canonical = langCode
            }
            guard !canonical.isEmpty, seen.insert(canonical).inserted else { continue }
            result.append(canonical)
        }
        return result.isEmpty ? fallback : result
    }

    /// Returns human-readable localized display name for a language code in the given locale.
    public static func localizedName(for code: String, in locale: Locale = .current) -> String {
        locale.localizedString(forIdentifier: code) ?? code
    }

    /// Returns sorted language options (code, name) for UI pickers.
    public static func sortedLanguages(
        from codes: [String] = fallbackLanguageCodes,
        in locale: Locale = .current
    ) -> [(code: String, name: String)] {
        codes
            .map { (code: $0, name: localizedName(for: $0, in: locale)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
