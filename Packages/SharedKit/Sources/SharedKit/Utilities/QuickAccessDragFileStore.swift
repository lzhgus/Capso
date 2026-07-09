// Packages/SharedKit/Sources/SharedKit/Utilities/QuickAccessDragFileStore.swift
import CoreGraphics
import Foundation

public enum QuickAccessDragFileStoreError: Error, Equatable {
    case encodingFailed
    case storageUnavailable
}

public final class QuickAccessDragFileStore {
    public typealias Encoder = (CGImage) -> Data?

    public static let defaultStaleFileAge: TimeInterval = 24 * 60 * 60

    public let directory: URL
    public let staleFileAge: TimeInterval

    private let fileManager: FileManager
    private let encoder: Encoder?
    private var cachedFileURLs: [UUID: URL] = [:]

    public init(
        directory: URL? = nil,
        staleFileAge: TimeInterval = QuickAccessDragFileStore.defaultStaleFileAge,
        fileManager: FileManager = .default,
        encoder: Encoder? = nil
    ) {
        self.directory = directory ?? fileManager.temporaryDirectory
            .appendingPathComponent("com.lifeisgoodlabs.Capso", isDirectory: true)
            .appendingPathComponent("QuickAccessDragFiles", isDirectory: true)
        self.staleFileAge = staleFileAge
        self.fileManager = fileManager
        self.encoder = encoder
    }

    public func fileURL(
        for image: CGImage,
        id: UUID,
        preset: ScreenshotOutputPreset = .losslessPNG,
        date: Date = Date(),
        sourceAppName: String? = nil,
        sourceWindowTitle: String? = nil,
        template: String? = nil
    ) throws -> URL {
        try prepareStorage()

        if let cachedURL = cachedFileURLs[id], fileManager.isReadableFile(atPath: cachedURL.path) {
            return cachedURL
        }

        guard let data = encodedData(from: image, preset: preset) else {
            throw QuickAccessDragFileStoreError.encodingFailed
        }

        let preferredURL = FileNaming.generateFileURL(
            in: directory,
            type: .screenshot,
            format: preset.fileFormat,
            date: date,
            sourceAppName: sourceAppName,
            sourceWindowTitle: sourceWindowTitle,
            template: template
        )
        let fileURL = availableFileURL(for: preferredURL)

        do {
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw QuickAccessDragFileStoreError.storageUnavailable
        }

        cachedFileURLs[id] = fileURL
        return fileURL
    }

    @discardableResult
    public func pruneStaleFiles(referenceDate: Date = Date()) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        let preservedURLs = Set(cachedFileURLs.values.map { $0.standardizedFileURL })
        let cutoff = referenceDate.addingTimeInterval(-staleFileAge)
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var removed: [URL] = []
        for fileURL in fileURLs where Self.prunableExtensions.contains(fileURL.pathExtension.lowercased()) {
            let standardizedURL = fileURL.standardizedFileURL
            guard !preservedURLs.contains(standardizedURL) else { continue }

            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true,
                  let modificationDate = values.contentModificationDate,
                  modificationDate < cutoff else { continue }

            try fileManager.removeItem(at: fileURL)
            removed.append(fileURL)
        }

        return removed
    }

    public func removeFile(for id: UUID) throws {
        guard let fileURL = cachedFileURLs.removeValue(forKey: id),
              fileManager.fileExists(atPath: fileURL.path) else { return }

        try fileManager.removeItem(at: fileURL)
    }

    private static let prunableExtensions: Set<String> = ["png", "jpg", "jpeg"]

    private func encodedData(from image: CGImage, preset: ScreenshotOutputPreset) -> Data? {
        if let encoder {
            return encoder(image)
        }

        switch preset.fileFormat {
        case .png:
            return ImageUtilities.pngData(from: image)
        case .jpeg:
            return ImageUtilities.jpegData(from: image, quality: preset.jpegQuality ?? 0.85)
        case .mp4, .gif, .mov:
            return nil
        }
    }

    private func availableFileURL(for preferredURL: URL) -> URL {
        guard fileManager.fileExists(atPath: preferredURL.path) else {
            return preferredURL
        }

        let directory = preferredURL.deletingLastPathComponent()
        let baseName = preferredURL.deletingPathExtension().lastPathComponent
        let pathExtension = preferredURL.pathExtension

        var index = 2
        while true {
            let candidate = directory
                .appendingPathComponent("\(baseName) \(index)", isDirectory: false)
                .appendingPathExtension(pathExtension)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func prepareStorage() throws {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            _ = try pruneStaleFiles()
        } catch {
            throw QuickAccessDragFileStoreError.storageUnavailable
        }
    }
}
