// Packages/TranslationKit/Sources/TranslationKit/TranslationError.swift
import Foundation

/// Typed errors thrown by ``TranslationService``.
///
/// `TranslationError` conforms to `@unchecked Sendable` because
/// `sessionFailed(underlying:)` wraps an `any Error` existential, which the
/// Swift 6 compiler cannot statically verify as `Sendable`. The enum itself
/// carries no mutable shared state, so the unchecked annotation is safe.
public enum TranslationError: Error, @unchecked Sendable {
    /// Apple's framework does not support the detected source language.
    case sourceUnsupported(language: String)
    /// Detected source language equals the requested target.
    case sourceEqualsTarget(language: String)
    /// Needed language pack is not installed and the device is offline.
    case needsLanguagePackDownloadOffline
    /// Session returned a different number of translations than inputs.
    case translationCountMismatch(expected: Int, got: Int)
    /// Underlying `TranslationSession` failure.
    case sessionFailed(underlying: any Error)
}

extension TranslationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sourceUnsupported(let language):
            return String(
                localized: "Translation doesn't support \(language.uppercased()) yet.",
                comment: "Shown when the source language is not supported by Apple Translation."
            )
        case .sourceEqualsTarget(let language):
            return String(
                localized: "This text is already in \(language.uppercased()).",
                comment: "Shown when source and target language match."
            )
        case .needsLanguagePackDownloadOffline:
            return String(
                localized: "Connect to the Internet to download the translation languages.",
                comment: "Shown when a language pack is missing and the device is offline."
            )
        case .translationCountMismatch(let expected, let got):
            return String(
                localized: "Translation mismatch: expected \(expected), got \(got).",
                comment: "Shown when the translation session returns a wrong number of translations."
            )
        case .sessionFailed(let underlying):
            return String(
                localized: "Translation failed: \(underlying.localizedDescription)",
                comment: "Generic translation failure wrapping an underlying system error."
            )
        }
    }
}
