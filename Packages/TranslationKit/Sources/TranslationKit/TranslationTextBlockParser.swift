import Foundation

public enum TranslationTextBlock: Equatable, Sendable {
    case paragraph(String)
    case bulletList([String])
    case numberedList([NumberedTranslationItem])
}

public struct NumberedTranslationItem: Equatable, Sendable {
    public let number: Int
    public let text: String

    public init(number: Int, text: String) {
        self.number = number
        self.text = text
    }
}

public enum TranslationTextBlockParser {
    public static func parse(_ text: String) -> [TranslationTextBlock] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var blocks: [TranslationTextBlock] = []
        var bullets: [String] = []
        var numbers: [NumberedTranslationItem] = []
        var paragraphLines: [String] = []

        func flushBullets() {
            guard !bullets.isEmpty else { return }
            blocks.append(.bulletList(bullets))
            bullets = []
        }
        func flushNumbers() {
            guard !numbers.isEmpty else { return }
            blocks.append(.numberedList(numbers))
            numbers = []
        }
        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
            paragraphLines = []
        }
        func flushAll() {
            flushBullets()
            flushNumbers()
            flushParagraph()
        }

        let bulletPattern = try! NSRegularExpression(pattern: "^[•\\-\\*]\\s*", options: [])
        let numberPattern = try! NSRegularExpression(pattern: "^(\\d+)[\\.、)]\\s*", options: [])

        for line in lines {
            guard !line.isEmpty else {
                flushAll()
                continue
            }

            let range = NSRange(line.startIndex..., in: line)
            if let match = bulletPattern.firstMatch(in: line, range: range) {
                flushNumbers()
                flushParagraph()
                bullets.append((line as NSString).substring(from: match.range.upperBound))
                continue
            }
            if let match = numberPattern.firstMatch(in: line, range: range) {
                flushBullets()
                flushParagraph()
                let numberText = (line as NSString).substring(with: match.range(at: 1))
                numbers.append(NumberedTranslationItem(
                    number: Int(numberText) ?? numbers.count + 1,
                    text: (line as NSString).substring(from: match.range.upperBound)
                ))
                continue
            }

            flushBullets()
            flushNumbers()
            paragraphLines.append(line)
        }

        flushAll()
        return blocks
    }
}
