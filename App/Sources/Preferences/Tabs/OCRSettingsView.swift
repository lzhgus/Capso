// App/Sources/Preferences/Tabs/OCRSettingsView.swift
import SwiftUI
import Vision
import SharedKit

struct TextAndTranslationSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel
    @State private var supportedLanguages: [(code: String, name: String)] = []

    private let translationLanguages: [(code: String, name: String)] = [
        ("en",      "English"),
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("ja",      "日本語"),
        ("ko",      "한국어"),
        ("fr",      "Français"),
        ("de",      "Deutsch"),
        ("es",      "Español"),
        ("it",      "Italiano"),
        ("pt-BR",   "Português (Brasil)"),
        ("ru",      "Русский"),
        ("ar",      "العربية"),
        ("hi",      "हिन्दी"),
        ("nl",      "Nederlands"),
        ("pl",      "Polski"),
        ("tr",      "Türkçe"),
        ("uk",      "Українська"),
        ("id",      "Bahasa Indonesia"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Text & Translation")
                .font(.system(size: 20, weight: .bold))

            SettingGroup(title: "Text Recognition") {
                SettingCard {
                    SettingRow(label: "Keep Line Breaks", sublabel: "Preserve original line structure") {
                        Toggle("", isOn: $viewModel.ocrKeepLineBreaks)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Detect Links", sublabel: "Auto-detect and linkify URLs", showDivider: true) {
                        Toggle("", isOn: $viewModel.ocrDetectLinks)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            SettingGroup(title: "Translation") {
                SettingCard {
                    SettingRow(label: "Target Language", sublabel: "Language to translate text into") {
                        Picker("", selection: $viewModel.translationTargetLanguage) {
                            ForEach(translationLanguages, id: \.code) { lang in
                                Text(lang.name).tag(lang.code)
                            }
                        }
                        .frame(width: 180)
                    }
                    SettingRow(label: "Auto-Copy Translation", sublabel: "Copy result to clipboard automatically") {
                        Toggle("", isOn: $viewModel.translationAutoCopy)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Show Original Text", sublabel: "Display source text alongside translation") {
                        Toggle("", isOn: $viewModel.translationShowOriginal)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Auto-Dismiss", sublabel: "When to close the translation panel", showDivider: true) {
                        Picker("", selection: $viewModel.translationAutoDismiss) {
                            Text("Manual").tag(TranslationAutoDismiss.manual)
                            Text("Click outside").tag(TranslationAutoDismiss.clickOutside)
                            Text("After delay").tag(TranslationAutoDismiss.afterDelay)
                        }
                        .frame(width: 140)
                    }
                }
            }

            // TODO: Re-enable the "Language" group once OCRCoordinator actually
            // threads settings.ocrPrimaryLanguage into TextRecognizer. Today
            // TextRecognizer.swift:86 sets `request.recognitionLanguages` from
            // a local parameter and the setting value is never passed in —
            // selecting a language here would have no effect on recognition.
            // When wiring it back, also uncomment the `.onAppear` below.
            // SettingGroup(title: "Language") {
            //     SettingCard {
            //         SettingRow(label: "Primary Language", sublabel: "Auto-detect if unset") {
            //             Picker("", selection: Binding(
            //                 get: { viewModel.ocrPrimaryLanguage ?? "auto" },
            //                 set: { viewModel.ocrPrimaryLanguage = $0 == "auto" ? nil : $0 }
            //             )) {
            //                 Text("Auto").tag("auto")
            //                 ForEach(supportedLanguages, id: \.code) { lang in
            //                     Text(lang.name).tag(lang.code)
            //                 }
            //             }
            //             .frame(width: 160)
            //         }
            //     }
            // }
        }
        // .onAppear {
        //     loadSupportedLanguages()
        // }
    }

    private func loadSupportedLanguages() {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let codes = (try? request.supportedRecognitionLanguages()) ?? []
        let locale = Locale.current
        supportedLanguages = codes.compactMap { code in
            let name = locale.localizedString(forLanguageCode: code) ?? code
            return (code: code, name: name)
        }
    }


}
