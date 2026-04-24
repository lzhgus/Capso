// Packages/TranslationKit/Tests/TranslationKitTests/TranslatedRegionTests.swift
import Foundation
import Testing
import OCRKit
@testable import TranslationKit

@Suite("TranslatedRegion")
struct TranslatedRegionTests {
    @Test("stores original region and translation")
    func stores() {
        let region = TextRegion(
            text: "Hello",
            boundingBox: CGRect(x: 0, y: 0, width: 100, height: 20),
            confidence: 0.99
        )
        let translated = TranslatedRegion(
            original: region,
            translation: "你好",
            detectedSource: Locale.Language(identifier: "en")
        )
        #expect(translated.original.text == "Hello")
        #expect(translated.translation == "你好")
        #expect(translated.detectedSource.languageCode?.identifier == "en")
    }
}
