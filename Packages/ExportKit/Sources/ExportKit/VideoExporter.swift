// Packages/ExportKit/Sources/ExportKit/VideoExporter.swift
import Foundation

public enum VideoExporter {
    /// Export a source .mov recording to the specified format with quality preset.
    /// Returns the URL of the exported file.
    public static func export(
        source: URL,
        options: ExportOptions,
        progress: (@Sendable (Double) -> Void)? = nil,
        status: (@Sendable (ExportStatus) -> Void)? = nil
    ) async throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw ExportError.exportSessionFailed("Source file not found at: \(source.path(percentEncoded: false))")
        }

        switch options.format {
        case .mp4:
            return try await MP4Exporter.export(
                source: source,
                quality: options.quality,
                destination: options.destination,
                timeRange: options.timeRange,
                progress: progress,
                status: status
            )
        case .gif:
            return try await GIFExporter.export(
                source: source,
                quality: options.quality,
                destination: options.destination,
                progress: progress,
                status: status
            )
        }
    }
}
