import Foundation
import CoreGraphics
import OCRKit

public enum TypedTranslationInputError: LocalizedError, Sendable {
    case empty

    public var errorDescription: String? {
        switch self {
        case .empty:
            String(localized: "No text to translate.")
        }
    }
}

public struct TypedTranslationInput: Sendable {
    public let rawText: String

    public init(rawText: String) {
        self.rawText = rawText
    }

    public var translationText: String {
        rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var canSubmit: Bool {
        !translationText.isEmpty
    }

    public func makeTextRegion() throws -> TextRegion {
        guard canSubmit else { throw TypedTranslationInputError.empty }
        return TextRegion(text: translationText, boundingBox: .zero, confidence: 1)
    }
}
