// Packages/TranslationKit/Sources/TranslationKit/TranslatedRegion.swift
import Foundation
import OCRKit

/// A translated text region. Pairs the original `TextRegion` (with bounding box)
/// with the translated string and the source language Apple actually detected.
public struct TranslatedRegion: Identifiable, Sendable {
    public let id: UUID
    public let original: TextRegion
    public let translation: String
    public let detectedSource: Locale.Language

    public init(
        original: TextRegion,
        translation: String,
        detectedSource: Locale.Language
    ) {
        self.id = original.id
        self.original = original
        self.translation = translation
        self.detectedSource = detectedSource
    }
}
