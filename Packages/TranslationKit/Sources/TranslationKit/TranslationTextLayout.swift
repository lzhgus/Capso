import Foundation
import OCRKit

/// Reconstructs readable source text from OCR regions without flattening
/// visually separate paragraphs, columns, lists, or code into one sentence.
public enum TranslationTextLayout {
    public static func compose(_ regions: [TextRegion]) -> String {
        let lines = regions.compactMap { region -> Line? in
            let text = region.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Line(text: text, frame: region.boundingBox)
        }
        guard !lines.isEmpty else { return "" }

        guard lines.contains(where: { !$0.frame.isEmpty }) else {
            return lines.map(\.text).joined(separator: "\n")
        }

        let heights = lines.map(\.frame.height).filter { $0 > 0 }.sorted()
        let medianHeight = heights[heights.count / 2]
        let sorted = lines.sorted { left, right in
            if abs(left.frame.midY - right.frame.midY) <= medianHeight * 0.5 {
                return left.frame.minX < right.frame.minX
            }
            return left.frame.minY < right.frame.minY
        }

        var paragraphs: [String] = []
        var current = sorted[0].text

        for index in sorted.indices.dropFirst() {
            let previous = sorted[index - 1]
            let line = sorted[index]
            if startsNewParagraph(after: previous, before: line, medianHeight: medianHeight) {
                paragraphs.append(current)
                current = line.text
                continue
            }

            let separator = isStructured(previous.text) || isStructured(line.text)
                ? "\n"
                : naturalJoiner(between: previous.text, and: line.text)
            current += separator + line.text
        }

        paragraphs.append(current)
        return paragraphs.joined(separator: "\n\n")
    }

    private static func startsNewParagraph(
        after previous: Line,
        before current: Line,
        medianHeight: CGFloat
    ) -> Bool {
        let sameRow = abs(previous.frame.midY - current.frame.midY) <= medianHeight * 0.5
        if sameRow {
            let horizontalGap = current.frame.minX - previous.frame.maxX
            return horizontalGap > medianHeight * 3
        }

        let verticalGap = current.frame.minY - previous.frame.maxY
        return verticalGap > medianHeight * 0.65
    }

    private static func naturalJoiner(between left: String, and right: String) -> String {
        guard let last = left.last, let first = right.first else { return "" }
        return isCJK(last) && isCJK(first) ? "" : " "
    }

    private static func isStructured(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let listPrefixes = ["• ", "- ", "* ", "– ", "— "]
        if listPrefixes.contains(where: trimmed.hasPrefix) {
            return true
        }
        if trimmed.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil {
            return true
        }

        let codePrefixes = [
            "let ", "var ", "func ", "class ", "struct ", "enum ", "if ",
            "for ", "while ", "guard ", "return ", "print(", "{", "}", "//",
        ]
        return text.hasPrefix("\t")
            || text.hasPrefix("    ")
            || codePrefixes.contains(where: trimmed.hasPrefix)
    }

    private static func isCJK(_ character: Character) -> Bool {
        let punctuation = "，。！？、；：（）【】《》“”‘’」』〉》"
        if punctuation.contains(character) { return true }

        return character.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x3040...0x30FF, 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }

    private struct Line {
        let text: String
        let frame: CGRect
    }
}
