import AppKit
import CoreGraphics
import ImageIO

public enum ClipboardPinContentResult {
    case image(CGImage)
    case tooLarge
    case unsupported
}

@MainActor
public enum ClipboardPinContentReader {
    private static let padding = NSEdgeInsets(top: 24, left: 26, bottom: 24, right: 26)
    private static let maxTextLength = 100_000
    private static let maxRichDataSize = 4 * 1_024 * 1_024
    private static let maxEncodedImageSize = 128 * 1_024 * 1_024
    private static let maxImagePixelCount = 40_000_000
    private static let maxImageDimension = 32_768

    private enum ImageReadResult {
        case image(CGImage)
        case tooLarge
        case unsupported
    }

    static func isSafeImageDimensions(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0,
              width <= maxImageDimension, height <= maxImageDimension else {
            return false
        }
        return width <= maxImagePixelCount / height
    }

    static func attributedText(from pasteboard: NSPasteboard) -> NSAttributedString? {
        for (pasteboardType, documentType) in [
            (NSPasteboard.PasteboardType.rtfd, NSAttributedString.DocumentType.rtfd),
            (.rtf, .rtf),
        ] {
            guard let data = pasteboard.data(forType: pasteboardType) else { continue }
            if let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: documentType],
                documentAttributes: nil
            ) {
                return attributed
            }
        }
        return nil
    }

    static func htmlText(from pasteboard: NSPasteboard) -> String? {
        guard let html = pasteboard.string(forType: .html) else { return nil }
        var text = replacingMatches(
            in: html,
            pattern: #"<(script|style)\b[^>]*>.*?</\1\s*>"#,
            with: ""
        )
        text = replacingMatches(
            in: text,
            pattern: #"<\s*(br\s*/?|/\s*(p|div|li|h[1-6]|tr))\s*>"#,
            with: "\n"
        )
        text = replacingMatches(in: text, pattern: #"<[^>]+>"#, with: "")
        text = decodeHTMLEntities(in: text)

        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let result = lines.joined(separator: "\n")
        return result.isEmpty ? nil : result
    }

    static func fileListText(from pasteboard: NSPasteboard) -> String? {
        let urls = fileURLs(from: pasteboard)
        guard !urls.isEmpty else { return nil }

        let displayed = urls.prefix(100).map { url in
            "\(url.lastPathComponent)\n\(url.path)"
        }
        var lines = displayed.joined(separator: "\n\n")
        if urls.count > displayed.count {
            lines += "\n\n+\(urls.count - displayed.count) more"
        }
        return lines
    }

    private static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        return pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] ?? []
    }

    private static func replacingMatches(
        in string: String,
        pattern: String,
        with replacement: String
    ) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return string
        }
        let range = NSRange(string.startIndex..., in: string)
        return expression.stringByReplacingMatches(
            in: string,
            range: range,
            withTemplate: replacement
        )
    }

    private static func decodeHTMLEntities(in string: String) -> String {
        let namedEntities = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"",
            "apos": "'", "#39": "'", "nbsp": " ",
        ]
        var result = ""
        var index = string.startIndex
        while index < string.endIndex {
            guard string[index] == "&" else {
                result.append(string[index])
                index = string.index(after: index)
                continue
            }

            let entityStart = string.index(after: index)
            var cursor = entityStart
            var semicolon: String.Index?
            for _ in 0..<12 where cursor < string.endIndex {
                if string[cursor] == ";" {
                    semicolon = cursor
                    break
                }
                if string[cursor] == "&" { break }
                cursor = string.index(after: cursor)
            }
            guard let semicolon else {
                result.append(string[index])
                index = string.index(after: index)
                continue
            }

            let entity = String(string[entityStart..<semicolon])
            let decoded: String?
            if let named = namedEntities[entity.lowercased()] {
                decoded = named
            } else if entity.lowercased().hasPrefix("#x"),
                      let value = UInt32(entity.dropFirst(2), radix: 16),
                      let scalar = UnicodeScalar(value) {
                decoded = String(scalar)
            } else if entity.hasPrefix("#"),
                      let value = UInt32(entity.dropFirst()),
                      let scalar = UnicodeScalar(value) {
                decoded = String(scalar)
            } else {
                decoded = nil
            }

            if let decoded {
                result.append(decoded)
                index = string.index(after: semicolon)
            } else {
                result.append(string[index])
                index = string.index(after: index)
            }
        }
        return result
    }

    public static func render(
        from pasteboard: NSPasteboard = .general,
        visibleFrame: CGRect? = nil
    ) -> ClipboardPinContentResult {
        if isOversized(pasteboard) {
            return .tooLarge
        }

        let urls = fileURLs(from: pasteboard)
        if urls.count == 1, ImageFileReader.isSupported(urls[0]) {
            switch readImage(at: urls[0]) {
            case let .image(image): return .image(image)
            case .tooLarge: return .tooLarge
            case .unsupported: break
            }
        }
        if !urls.isEmpty,
           let text = fileListText(from: pasteboard),
           let image = renderCard(plainAttributedString(text), visibleFrame: visibleFrame) {
            return .image(image)
        }

        if let attributed = attributedText(from: pasteboard),
           let image = renderCard(attributed, visibleFrame: visibleFrame) {
            return .image(image)
        }

        switch readImage(from: pasteboard) {
        case let .image(image): return .image(image)
        case .tooLarge: return .tooLarge
        case .unsupported: break
        }

        if let text = htmlText(from: pasteboard),
           let image = renderCard(plainAttributedString(text), visibleFrame: visibleFrame) {
            return .image(image)
        }

        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return .unsupported
        }

        let pathURL = URL(fileURLWithPath: text)
        if text.hasPrefix("/"), ImageFileReader.isSupported(pathURL) {
            switch readImage(at: pathURL) {
            case let .image(image): return .image(image)
            case .tooLarge: return .tooLarge
            case .unsupported: break
            }
        }

        if let color = clipboardColor(from: text),
           let image = renderColorCard(color: color, label: text) {
            return .image(image)
        }

        guard let image = renderCard(plainAttributedString(text), visibleFrame: visibleFrame) else {
            return .unsupported
        }
        return .image(image)
    }

    private static func readImage(at url: URL) -> ImageReadResult {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize else {
            return .unsupported
        }
        guard fileSize <= maxEncodedImageSize else { return .tooLarge }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return .unsupported
        }
        return readImage(from: source)
    }

    private static func readImage(from pasteboard: NSPasteboard) -> ImageReadResult {
        let types: [NSPasteboard.PasteboardType] = [
            .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("com.compuserve.gif"),
            .tiff,
        ]
        var foundOversizedData = false
        for type in types {
            guard let data = pasteboard.data(forType: type) else { continue }
            guard data.count <= maxEncodedImageSize else {
                foundOversizedData = true
                continue
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { continue }
            switch readImage(from: source) {
            case let .image(image): return .image(image)
            case .tooLarge: foundOversizedData = true
            case .unsupported: continue
            }
        }
        return foundOversizedData ? .tooLarge : .unsupported
    }

    private static func readImage(from source: CGImageSource) -> ImageReadResult {
        guard CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            return .unsupported
        }
        guard isSafeImageDimensions(width: width, height: height) else { return .tooLarge }

        let options = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false,
        ] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options),
              isSafeImageDimensions(width: image.width, height: image.height) else {
            return .unsupported
        }
        return .image(image)
    }

    private static func isOversized(_ pasteboard: NSPasteboard) -> Bool {
        for type in [NSPasteboard.PasteboardType.rtfd, .rtf, .html] {
            if let data = pasteboard.data(forType: type), data.count > maxRichDataSize {
                return true
            }
        }
        return pasteboard.string(forType: .string)?.utf16.count ?? 0 > maxTextLength
    }

    private static func plainAttributedString(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        )
    }

    private static func renderCard(
        _ attributed: NSAttributedString,
        visibleFrame: CGRect?
    ) -> CGImage? {
        let screenFrame = visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let maxContentWidth = max(320, min(760, screenFrame.width * 0.72))
        let measured = attributed.boundingRect(
            with: NSSize(width: maxContentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let width = max(320, ceil(measured.width + padding.left + padding.right))
        let height = min(8_000, max(120, ceil(measured.height + padding.top + padding.bottom)))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: Int(width),
                height: Int(height),
                bitsPerComponent: 8,
                bytesPerRow: Int(width) * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor.textBackgroundColor.usingColorSpace(.sRGB)?.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
            xRadius: 14,
            yRadius: 14
        ).fill()
        attributed.draw(
            with: NSRect(
                x: padding.left,
                y: padding.top,
                width: width - padding.left - padding.right,
                height: height - padding.top - padding.bottom
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return context.makeImage()
    }

    private static func clipboardColor(from text: String) -> NSColor? {
        if let hexadecimal = hexadecimalColor(from: text) {
            return hexadecimal
        }

        let lowercased = text.lowercased()
        let components: Substring
        if lowercased.hasPrefix("rgb("), lowercased.hasSuffix(")") {
            components = lowercased.dropFirst(4).dropLast()
        } else {
            components = Substring(lowercased)
        }
        let values = components.split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 3, values.allSatisfy({ (0...255).contains($0) }) else { return nil }
        let divisor = values.allSatisfy({ $0 <= 1 }) ? 1.0 : 255.0
        return NSColor(
            srgbRed: values[0] / divisor,
            green: values[1] / divisor,
            blue: values[2] / divisor,
            alpha: 1
        )
    }

    private static func hexadecimalColor(from text: String) -> NSColor? {
        guard text.hasPrefix("#") else { return nil }
        let hex = String(text.dropFirst())
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func renderColorCard(color: NSColor, label: String) -> CGImage? {
        let width = 360
        let height = 180
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let srgb = color.usingColorSpace(.sRGB) else {
            return nil
        }

        context.setFillColor(srgb.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }

        let foreground: NSColor = srgb.brightnessComponent > 0.58 ? .black : .white
        NSString(string: label.uppercased()).draw(
            at: NSPoint(x: 24, y: height - 52),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: foreground,
            ]
        )
        return context.makeImage()
    }
}
