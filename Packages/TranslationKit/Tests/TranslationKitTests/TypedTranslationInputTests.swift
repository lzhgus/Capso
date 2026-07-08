import CoreGraphics
import Testing
@testable import TranslationKit

@Suite("TypedTranslationInput")
struct TypedTranslationInputTests {
    @Test("trims outer whitespace while preserving typed line breaks")
    func trimmedTextPreservesLineBreaks() throws {
        let input = TypedTranslationInput(rawText: "  Hello\nworld  \n")

        #expect(input.translationText == "Hello\nworld")
        #expect(input.canSubmit)
    }

    @Test("blank input cannot be submitted")
    func blankInputCannotSubmit() {
        let input = TypedTranslationInput(rawText: " \n\t ")

        #expect(input.translationText == "")
        #expect(!input.canSubmit)
    }

    @Test("creates a text region from typed input")
    func createsTextRegion() throws {
        let region = try TypedTranslationInput(rawText: "  Bonjour  ").makeTextRegion()

        #expect(region.text == "Bonjour")
        #expect(region.boundingBox == CGRect.zero)
        #expect(region.confidence == 1)
    }
}
