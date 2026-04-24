// Packages/TranslationKit/Sources/TranslationKit/TranslationService.swift
import Foundation
import OCRKit
import NaturalLanguage

/// High-level translation façade used by the app.
/// Input: already-OCR'd `TextRegion`s + a target BCP-47 code.
/// Output: `TranslatedRegion`s in the same order, or a typed `TranslationError`.
///
/// Declared as an `actor` to serialize in-flight requests and host future
/// caching / TranslationSession lifecycle state.
public actor TranslationService {
    private let session: TranslationSessioning

    public init(session: TranslationSessioning) {
        self.session = session
    }

    public func translate(
        regions: [TextRegion],
        target: String
    ) async throws -> [TranslatedRegion] {
        // Filter empty / whitespace-only text up front — Apple's API doesn't like
        // empty strings and we'd waste a round-trip.
        let meaningful = regions.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !meaningful.isEmpty else { return [] }

        // Pre-detect source language with NaturalLanguage to avoid Apple's
        // auto-detection dialog, which requires a visible UI host and crashes
        // when attached to our hidden driver window. Fall back to the user's
        // current locale if detection is inconclusive.
        let combined = meaningful.map(\.text).joined(separator: "\n")
        let detectedFrom = Self.detectLanguage(combined)

        let sessionResult = try await session.translate(
            meaningful.map(\.text),
            from: detectedFrom,
            to: target
        )

        guard sessionResult.translations.count == meaningful.count else {
            throw TranslationError.translationCountMismatch(
                expected: meaningful.count,
                got: sessionResult.translations.count
            )
        }

        if sessionResult.detectedSource == target {
            throw TranslationError.sourceEqualsTarget(language: target)
        }

        return zip(meaningful, sessionResult.translations).map { region, translation in
            TranslatedRegion(
                original: region,
                translation: translation,
                detectedSource: Locale.Language(identifier: sessionResult.detectedSource)
            )
        }
    }

    /// Detect the dominant language of a piece of text using Apple's
    /// NaturalLanguage framework. Returns a BCP-47 code (e.g. "en", "zh-Hans").
    /// Returns `nil` if detection is inconclusive — caller decides the fallback.
    private static func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage else { return nil }
        // NLLanguage raw values are BCP-47 already (e.g. "en", "zh-Hans", "ja")
        return lang.rawValue
    }
}
