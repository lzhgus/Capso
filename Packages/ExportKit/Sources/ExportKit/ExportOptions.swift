// Packages/ExportKit/Sources/ExportKit/ExportOptions.swift
import Foundation
import CoreMedia
import SharedKit

public enum ExportFormat: String, Sendable {
    case mp4
    case gif
}

public struct ExportOptions: Sendable {
    public let format: ExportFormat
    public let quality: ExportQuality
    public let destination: URL
    /// Optional time range to export. When set, only this portion of the source is exported.
    public let timeRange: CMTimeRange?

    public init(format: ExportFormat, quality: ExportQuality, destination: URL, timeRange: CMTimeRange? = nil) {
        self.format = format
        self.quality = quality
        self.destination = destination
        self.timeRange = timeRange
    }
}

public enum ExportError: Error, Sendable {
    case sourceFileNotFound
    case exportSessionFailed(String)
    case frameExtractionFailed
    case gifCreationFailed
    case cancelled
}

public enum ExportStage: String, Sendable {
    case preparing
    case trimming
    case compositing
    case encoding
    case finalizing

    public var userDescription: String {
        switch self {
        case .preparing:
            return "Preparing export…"
        case .trimming:
            return "Applying trims…"
        case .compositing:
            return "Rendering edited frames…"
        case .encoding:
            return "Encoding video…"
        case .finalizing:
            return "Finalizing file…"
        }
    }
}

public struct ExportStatus: Sendable {
    public let stage: ExportStage
    public let fractionCompleted: Double

    public init(stage: ExportStage, fractionCompleted: Double) {
        self.stage = stage
        self.fractionCompleted = fractionCompleted
    }
}
