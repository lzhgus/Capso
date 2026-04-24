// Packages/TranslationKit/Tests/TranslationKitTests/TranslationErrorTests.swift
import Foundation
import Testing
@testable import TranslationKit

@Suite("TranslationError")
struct TranslationErrorTests {
    @Test("sourceUnsupported carries the language identifier")
    func sourceUnsupported() {
        let err = TranslationError.sourceUnsupported(language: "th")
        if case .sourceUnsupported(let lang) = err {
            #expect(lang == "th")
        } else {
            Issue.record("Expected .sourceUnsupported")
        }
    }

    @Test("localizedDescription is human readable for every case")
    func descriptions() {
        let cases: [TranslationError] = [
            .sourceUnsupported(language: "th"),
            .sourceEqualsTarget(language: "en"),
            .needsLanguagePackDownloadOffline,
            .translationCountMismatch(expected: 3, got: 2),
            .sessionFailed(underlying: NSError(domain: "x", code: 1))
        ]
        for err in cases {
            #expect(!err.localizedDescription.isEmpty)
        }
    }
}
