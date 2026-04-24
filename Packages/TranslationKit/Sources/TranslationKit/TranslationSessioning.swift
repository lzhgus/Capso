// Packages/TranslationKit/Sources/TranslationKit/TranslationSessioning.swift
import Foundation

/// Result returned by a translation session batch call.
/// Named struct (not a tuple) so the API can evolve without breaking consumers.
public struct TranslationSessionResult: Sendable {
    public let translations: [String]
    public let detectedSource: String

    public init(translations: [String], detectedSource: String) {
        self.translations = translations
        self.detectedSource = detectedSource
    }
}

/// Abstraction over Apple's `TranslationSession` so `TranslationService` is testable.
/// Real implementation wraps `TranslationSession`; tests provide an in-memory fake.
public protocol TranslationSessioning: Sendable {
    /// Translate strings in order, returning translations in matching order.
    /// On success, returns an array of the same length as `sources`.
    /// Throws `TranslationError` on failure.
    func translate(
        _ sources: [String],
        from: String?,      // BCP-47; nil = auto-detect
        to target: String
    ) async throws -> TranslationSessionResult

    /// Non-blocking check of whether the language pair is installed.
    /// Used to preflight before showing the system download prompt.
    func status(from: String, to: String) async -> LanguagePairStatus
}

public enum LanguagePairStatus: Sendable {
    case installed
    case supported        // can be downloaded
    case unsupported
}
