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

    public static func generateName(for type: CaptureType, date: Date = Date(), sourceAppName: String? = nil) -> String {
        let prefix = switch type {
        case .screenshot: "Capso Screenshot"
        case .recording: "Capso Recording"
        }
        let source = sanitizedSourceAppName(sourceAppName).map { " - \($0)" } ?? ""
        let dateString = dateFormatter.string(from: date)
        let timeString = timeFormatter.string(from: date)
        return "\(prefix)\(source) \(dateString) at \(timeString)"
    }

    public static func fileExtension(for format: FileFormat) -> String {
        format.rawValue
    }

    public static func generateFileName(
        for type: CaptureType,
        format: FileFormat,
        date: Date = Date(),
        sourceAppName: String? = nil
    ) -> String {
        "\(generateName(for: type, date: date, sourceAppName: sourceAppName)).\(fileExtension(for: format))"
    }

    public static func generateFileURL(
        in directory: URL,
        type: CaptureType,
        format: FileFormat,
        date: Date = Date(),
        sourceAppName: String? = nil
    ) -> URL {
        directory.appendingPathComponent(
            generateFileName(for: type, format: format, date: date, sourceAppName: sourceAppName)
        )
    }

    public static func monthlyDirectory(in baseDirectory: URL, date: Date = Date()) -> URL {
        baseDirectory.appendingPathComponent(monthFormatter.string(from: date), isDirectory: true)
    }

    private static func sanitizedSourceAppName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let invalidCharacters = CharacterSet(charactersIn: "/:")
        let sanitized = trimmed
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }
}
