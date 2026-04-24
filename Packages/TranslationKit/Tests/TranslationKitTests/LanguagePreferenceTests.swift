// Packages/TranslationKit/Tests/TranslationKitTests/LanguagePreferenceTests.swift
import Foundation
import Testing
@testable import TranslationKit

@Suite("LanguagePreference")
struct LanguagePreferenceTests {
    @Test("defaultTarget returns system language code for supported locales")
    func defaultTargetSupported() {
        let en = Locale(identifier: "en_US")
        #expect(LanguagePreference.defaultTarget(for: en) == "en")

        let zh = Locale(identifier: "zh_Hans_CN")
        #expect(LanguagePreference.defaultTarget(for: zh) == "zh-Hans")

        let ja = Locale(identifier: "ja_JP")
        #expect(LanguagePreference.defaultTarget(for: ja) == "ja")

        let ko = Locale(identifier: "ko_KR")
        #expect(LanguagePreference.defaultTarget(for: ko) == "ko")
    }

    @Test("defaultTarget falls back to English for unsupported locales")
    func defaultTargetFallback() {
        let th = Locale(identifier: "th_TH")
        #expect(LanguagePreference.defaultTarget(for: th) == "en")
    }

    @Test("isSupported matches Apple's documented language list")
    func isSupported() {
        #expect(LanguagePreference.isSupported("en"))
        #expect(LanguagePreference.isSupported("zh-Hans"))
        #expect(LanguagePreference.isSupported("ja"))
        #expect(!LanguagePreference.isSupported("th"))
        #expect(!LanguagePreference.isSupported("vi"))
    }

    @Test("Chinese regional locales without script map correctly")
    func chineseRegions() {
        #expect(LanguagePreference.defaultTarget(for: Locale(identifier: "zh_TW")) == "zh-Hant")
        #expect(LanguagePreference.defaultTarget(for: Locale(identifier: "zh_HK")) == "zh-Hant")
        #expect(LanguagePreference.defaultTarget(for: Locale(identifier: "zh_MO")) == "zh-Hant")
        #expect(LanguagePreference.defaultTarget(for: Locale(identifier: "zh_CN")) == "zh-Hans")
        #expect(LanguagePreference.defaultTarget(for: Locale(identifier: "zh_SG")) == "zh-Hans")
    }

    @Test("Portuguese locales map to pt-BR")
    func portuguese() {
        #expect(LanguagePreference.defaultTarget(for: Locale(identifier: "pt_BR")) == "pt-BR")
        #expect(LanguagePreference.defaultTarget(for: Locale(identifier: "pt_PT")) == "pt-BR")
        #expect(LanguagePreference.isSupported("pt-BR"))
        #expect(!LanguagePreference.isSupported("pt"))
    }
}
