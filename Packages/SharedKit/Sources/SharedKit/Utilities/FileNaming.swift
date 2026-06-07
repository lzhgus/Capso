// Packages/SharedKit/Sources/SharedKit/Utilities/FileNaming.swift
import Foundation
import UniformTypeIdentifiers

public enum CaptureType: Sendable {
    case screenshot
    case recording
}

public enum FileFormat: String, Sendable {
    case png
    case jpeg
    case mp4
    case gif
    case mov

    public init?(pathExtension: String) {
        switch pathExtension.lowercased() {
        case "png":
            self = .png
        case "jpg", "jpeg":
            self = .jpeg
        case "mp4":
            self = .mp4
        case "gif":
            self = .gif
        case "mov":
            self = .mov
        default:
            return nil
        }
    }

    public var contentType: UTType {
        switch self {
        case .png:
            return .png
        case .jpeg:
            return .jpeg
        case .mp4:
            return .mpeg4Movie
        case .gif:
            return .gif
        case .mov:
            return .quickTimeMovie
        }
    }
}

public enum FileNaming {
    public static let defaultScreenshotTemplate = "Capso Screenshot{source} {timestamp}"
    public static let defaultRecordingTemplate = "Capso Recording {timestamp}"

    private static let maxBaseNameUTF8Length = 200
    private static let randomAlphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH.mm.ss"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()

    public static func generateName(
        for type: CaptureType,
        date: Date = Date(),
        sourceAppName: String? = nil,
        sourceWindowTitle: String? = nil,
        template: String? = nil
    ) -> String {
        let fallback = defaultTemplate(for: type)
        let rawTemplate = template ?? fallback
        let effectiveTemplate = rawTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallback
            : rawTemplate
        let rendered = renderTemplate(
            effectiveTemplate,
            date: date,
            sourceAppName: sourceAppName,
            sourceWindowTitle: sourceWindowTitle
        )
        let sanitized = sanitizeRenderedBaseName(rendered)
        if sanitized.isEmpty && effectiveTemplate != fallback {
            return generateName(
                for: type,
                date: date,
                sourceAppName: sourceAppName,
                sourceWindowTitle: sourceWindowTitle,
                template: fallback
            )
        }
        return sanitized.isEmpty ? fallbackBaseName(for: type) : sanitized
    }

    public static func fileExtension(for format: FileFormat) -> String {
        format.rawValue
    }

    public static func generateFileName(
        for type: CaptureType,
        format: FileFormat,
        date: Date = Date(),
        sourceAppName: String? = nil,
        sourceWindowTitle: String? = nil,
        template: String? = nil
    ) -> String {
        "\(generateName(for: type, date: date, sourceAppName: sourceAppName, sourceWindowTitle: sourceWindowTitle, template: template)).\(fileExtension(for: format))"
    }

    public static func generateFileURL(
        in directory: URL,
        type: CaptureType,
        format: FileFormat,
        date: Date = Date(),
        sourceAppName: String? = nil,
        sourceWindowTitle: String? = nil,
        template: String? = nil
    ) -> URL {
        directory.appendingPathComponent(
            generateFileName(
                for: type,
                format: format,
                date: date,
                sourceAppName: sourceAppName,
                sourceWindowTitle: sourceWindowTitle,
                template: template
            )
        )
    }

    public static func monthlyDirectory(in baseDirectory: URL, date: Date = Date()) -> URL {
        baseDirectory.appendingPathComponent(monthFormatter.string(from: date), isDirectory: true)
    }

    private static func renderTemplate(
        _ template: String,
        date: Date,
        sourceAppName: String?,
        sourceWindowTitle: String?
    ) -> String {
        let app = sanitizedTokenValue(sourceAppName) ?? ""
        let window = sanitizedTokenValue(sourceWindowTitle) ?? ""
        let dateString = dateFormatter.string(from: date)
        let timeString = timeFormatter.string(from: date)
        let timestamp = "\(dateString) at \(timeString)"
        let replacements: [String: String] = [
            "{date}": dateString,
            "{time}": timeString,
            "{timestamp}": timestamp,
            "{source}": app.isEmpty ? "" : " - \(app)",
            "{app}": app,
            "{window}": window,
        ]

        var output = template
        for (token, value) in replacements {
            output = output.replacingOccurrences(of: token, with: value)
        }
        while let range = output.range(of: "{random}") {
            output.replaceSubrange(range, with: randomToken())
        }
        return output
    }

    private static func sanitizedTokenValue(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sanitized = sanitizeFilenameScalars(in: trimmed)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }

    private static func sanitizeRenderedBaseName(_ name: String) -> String {
        var sanitized = sanitizeFilenameScalars(in: name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while sanitized.hasSuffix(".") {
            sanitized.removeLast()
        }
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return capToByteLength(sanitized, bytes: maxBaseNameUTF8Length)
    }

    private static func sanitizeFilenameScalars(in value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "/", ":", "\0":
                result.append("-")
            default:
                if scalar.value >= 0x20 {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }

    private static func capToByteLength(_ value: String, bytes: Int) -> String {
        guard value.utf8.count > bytes else { return value }
        var result = ""
        var usedBytes = 0
        for scalar in value.unicodeScalars {
            let scalarBytes = String(scalar).utf8.count
            guard usedBytes + scalarBytes <= bytes else { break }
            result.unicodeScalars.append(scalar)
            usedBytes += scalarBytes
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func randomToken(length: Int = 8) -> String {
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            result.append(randomAlphabet[Int.random(in: 0..<randomAlphabet.count)])
        }
        return result
    }

    private static func defaultTemplate(for type: CaptureType) -> String {
        switch type {
        case .screenshot:
            defaultScreenshotTemplate
        case .recording:
            defaultRecordingTemplate
        }
    }

    private static func fallbackBaseName(for type: CaptureType) -> String {
        switch type {
        case .screenshot:
            "Capso Screenshot"
        case .recording:
            "Capso Recording"
        }
    }
}
