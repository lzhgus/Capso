import Foundation
import CoreGraphics

public struct TranslationTextLine: Sendable {
    public let text: String
    public let frame: CGRect

    public init(text: String, frame: CGRect) {
        self.text = text
        self.frame = frame
    }
}

/// Reconstructs readable source text from OCR regions without flattening
/// visually separate paragraphs, columns, lists, or code into one sentence.
public enum TranslationTextLayout {
    public static func compose(_ sourceLines: [TranslationTextLine]) -> String {
        let lines = sourceLines.compactMap { sourceLine -> Line? in
            var text = sourceLine.text.trimmingCharacters(in: .newlines)
            while text.last?.isWhitespace == true {
                text.removeLast()
            }
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return Line(text: text, frame: sourceLine.frame)
        }
        guard !lines.isEmpty else { return "" }

        guard lines.contains(where: { !$0.frame.isEmpty }) else {
            return lines.map(\.text).joined(separator: "\n")
        }

        let heights = lines.map(\.frame.height).filter { $0 > 0 }.sorted()
        let medianHeight = heights[heights.count / 2]
        let rowOrdered = lines.sorted { left, right in
            if abs(left.frame.midY - right.frame.midY) <= medianHeight * 0.5 {
                return left.frame.minX < right.frame.minX
            }
            return left.frame.minY < right.frame.minY
        }
        let sorted = readingOrder(
            lines: lines,
            rowOrderedFallback: rowOrdered,
            medianHeight: medianHeight
        )

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

    private static func readingOrder(
        lines: [Line],
        rowOrderedFallback: [Line],
        medianHeight: CGFloat
    ) -> [Line] {
        guard lines.count >= 4 else { return rowOrderedFallback }

        let xTolerance = max(48, medianHeight * 3)
        var columns: [Column] = []
        for line in lines.sorted(by: {
            $0.frame.minX == $1.frame.minX
                ? $0.frame.minY < $1.frame.minY
                : $0.frame.minX < $1.frame.minX
        }) {
            let nearest = columns.indices.min {
                abs(columns[$0].anchorX - line.frame.minX)
                    < abs(columns[$1].anchorX - line.frame.minX)
            }
            if let nearest,
               abs(columns[nearest].anchorX - line.frame.minX) <= xTolerance {
                columns[nearest].append(line)
            } else {
                columns.append(Column(line: line))
            }
        }

        let strongColumns = columns.filter { $0.lines.count >= 2 }
        guard strongColumns.count >= 2,
              strongColumns.reduce(0, { $0 + $1.lines.count }) == lines.count,
              hasVerticallyOverlappingColumns(strongColumns, tolerance: medianHeight) else {
            return rowOrderedFallback
        }

        return strongColumns.sorted { $0.anchorX < $1.anchorX }.flatMap { column in
            column.lines.sorted {
                $0.frame.minY == $1.frame.minY
                    ? $0.frame.minX < $1.frame.minX
                    : $0.frame.minY < $1.frame.minY
            }
        }
    }

    private static func hasVerticallyOverlappingColumns(
        _ columns: [Column],
        tolerance: CGFloat
    ) -> Bool {
        for leftIndex in columns.indices {
            for rightIndex in columns.indices where rightIndex > leftIndex {
                let leftRange = columns[leftIndex].verticalRange
                let rightRange = columns[rightIndex].verticalRange
                if min(leftRange.upperBound, rightRange.upperBound)
                    - max(leftRange.lowerBound, rightRange.lowerBound) >= -tolerance {
                    return true
                }
            }
        }
        return false
    }

    private static func startsNewParagraph(
        after previous: Line,
        before current: Line,
        medianHeight: CGFloat
    ) -> Bool {
        if current.frame.minY < previous.frame.minY - medianHeight * 0.5 {
            return true
        }
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
        if trimmed.range(of: #"^\d+[.)、]\s*"#, options: .regularExpression) != nil {
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

    private struct Column {
        private(set) var anchorX: CGFloat
        private(set) var lines: [Line]

        init(line: Line) {
            anchorX = line.frame.minX
            lines = [line]
        }

        mutating func append(_ line: Line) {
            lines.append(line)
            anchorX = lines.map(\.frame.minX).reduce(0, +) / CGFloat(lines.count)
        }

        var verticalRange: ClosedRange<CGFloat> {
            let minimum = lines.map(\.frame.minY).min() ?? 0
            let maximum = lines.map(\.frame.maxY).max() ?? 0
            return minimum...maximum
        }
    }
}
