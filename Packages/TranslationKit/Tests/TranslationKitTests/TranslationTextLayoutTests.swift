import CoreGraphics
import Testing
@testable import TranslationKit

@Suite("Translation text layout")
struct TranslationTextLayoutTests {
    @Test("Visual line wraps stay in one paragraph while larger gaps start a new paragraph")
    func preservesVisualParagraphs() {
        let regions = [
            region("A readable translation", x: 20, y: 10, width: 180),
            region("should keep its context.", x: 20, y: 34, width: 170),
            region("A second paragraph stays separate.", x: 20, y: 82, width: 230),
        ]

        #expect(TranslationTextLayout.compose(regions) == "A readable translation should keep its context.\n\nA second paragraph stays separate.")
    }

    @Test("CJK visual line wraps do not gain spaces")
    func joinsCJKWithoutSpaces() {
        let regions = [
            region("翻译结果应该保持", x: 10, y: 10, width: 140),
            region("自然的中文阅读节奏。", x: 10, y: 34, width: 160),
        ]

        #expect(TranslationTextLayout.compose(regions) == "翻译结果应该保持自然的中文阅读节奏。")
    }

    @Test("List items and code-like lines keep their line breaks")
    func preservesStructuredLines() {
        let regions = [
            region("• First item", x: 10, y: 10, width: 100),
            region("• Second item", x: 10, y: 34, width: 110),
            region("let value = 42", x: 10, y: 80, width: 120),
            region("print(value)", x: 30, y: 104, width: 90),
        ]

        #expect(TranslationTextLayout.compose(regions) == "• First item\n• Second item\n\nlet value = 42\nprint(value)")
    }

    @Test("Separated columns are never flattened into one sentence")
    func separatesColumnsOnTheSameRow() {
        let regions = [
            region("Left column", x: 10, y: 10, width: 100),
            region("Right column", x: 360, y: 10, width: 110),
        ]

        #expect(TranslationTextLayout.compose(regions) == "Left column\n\nRight column")
    }

    @Test("Multi-line columns read top-to-bottom instead of interleaving by row")
    func ordersMultiLineColumns() {
        let regions = [
            region("Left one", x: 10, y: 10, width: 100),
            region("Right one", x: 360, y: 10, width: 110),
            region("Left two", x: 10, y: 34, width: 100),
            region("Right two", x: 360, y: 34, width: 110),
        ]

        #expect(TranslationTextLayout.compose(regions) == "Left one Left two\n\nRight one Right two")
    }

    @Test("Indented code keeps indentation and explicit lines")
    func preservesCodeIndentation() {
        let regions = [
            region("func run() {", x: 10, y: 10, width: 100),
            region("    continuation()", x: 30, y: 34, width: 140),
            region("}", x: 10, y: 58, width: 10),
        ]

        #expect(TranslationTextLayout.compose(regions) == "func run() {\n    continuation()\n}")
    }

    @Test("Chinese numbered lists keep item boundaries")
    func preservesChineseNumberedLists() {
        let regions = [
            region("1、第一项", x: 10, y: 10, width: 80),
            region("2、第二项", x: 10, y: 34, width: 80),
        ]

        #expect(TranslationTextLayout.compose(regions) == "1、第一项\n2、第二项")
    }

    @Test("Text without OCR geometry keeps explicit line breaks")
    func preservesTextOnlyInput() {
        let regions = [
            TranslationTextLine(text: "First line\n\nSecond line", frame: .zero),
        ]

        #expect(TranslationTextLayout.compose(regions) == "First line\n\nSecond line")
    }

    private func region(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat = 20
    ) -> TranslationTextLine {
        TranslationTextLine(
            text: text,
            frame: CGRect(x: x, y: y, width: width, height: height)
        )
    }
}

@Suite("Translation text blocks")
struct TranslationTextBlockParserTests {
    @Test("Plain lines keep explicit breaks instead of becoming one dense sentence")
    func keepsPlainLineBreaks() {
        #expect(
            TranslationTextBlockParser.parse("First line\nSecond line") == [
                .paragraph("First line\nSecond line"),
            ]
        )
    }

    @Test("Bulleted and numbered lines remain semantic lists")
    func parsesLists() {
        #expect(
            TranslationTextBlockParser.parse("• Alpha\n• Beta\n\n1. One\n2. Two") == [
                .bulletList(["Alpha", "Beta"]),
                .numberedList([
                    NumberedTranslationItem(number: 1, text: "One"),
                    NumberedTranslationItem(number: 2, text: "Two"),
                ]),
            ]
        )
    }
}
