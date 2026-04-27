// App/Sources/History/HistoryCoordinator.swift
import AppKit
import AVFoundation
import Observation
import CaptureKit
import ExportKit
import HistoryKit
import ShareKit
import SharedKit

@MainActor
@Observable
final class HistoryCoordinator {
    let settings: AppSettings
    private let store: HistoryStore?
    private(set) var entries: [HistoryEntry] = []
    private(set) var totalSize: Int64 = 0
    var currentFilter: HistoryFilter = .all
    /// Cloud sharing coordinator — set by AppDelegate after creation.
    /// Non-nil only when cloud sharing is configured.
    var shareCoordinator: ShareCoordinator?

    private var historyWindow: HistoryWindow?

    init(settings: AppSettings) {
        self.settings = settings
        self.store = try? HistoryStore()
    }

    // MARK: - Window

    func showWindow() {
        if let historyWindow {
            historyWindow.show()
            return
        }
        let window = HistoryWindow(coordinator: self)
        self.historyWindow = window
        window.show()
    }

    // MARK: - Data Loading

    func loadEntries() {
        guard let store else { return }
        do {
            entries = try store.fetchAll(filter: currentFilter)
            totalSize = try store.totalFileSize()
        } catch {
            print("Failed to load history: \(error)")
        }
    }

    func setFilter(_ filter: HistoryFilter) {
        currentFilter = filter
        loadEntries()
    }

    // MARK: - Cloud URL

    /// Persist the cloud-share URL for a history entry after a successful upload.
    /// Can be called from any context (e.g. QuickAccess upload callback).
    func setCloudURL(id: UUID, url: String) {
        guard let store else { return }
        do {
            try store.setCloudURL(id: id, url: url)
            // Refresh in-memory list so the History UI reflects the change.
            loadEntries()
        } catch {
            print("Failed to persist cloud URL: \(error)")
        }
    }

    /// Upload a history entry to the cloud and persist the resulting URL.
    /// Returns the cloud URL on success. Throws on failure.
    ///
    /// For recordings and GIFs, transcodes the on-disk .mov to a web-friendly
    /// format (H.264 .mp4 or actual .gif) BEFORE upload. Without this, Chrome
    /// and Firefox often fail to play .mov inline even when the codec is H.264 —
    /// the user gets a blank page when opening the share link. Screenshots
    /// (.png) upload as-is.
    func uploadEntry(_ entry: HistoryEntry) async throws -> URL {
        guard let coord = shareCoordinator else {
            throw ShareError.notConfigured
        }
        guard let sourceURL = fullImageURL(for: entry) else {
            throw ShareError.unknown("Source file not found")
        }

        let uploadURL: URL
        let contentType: String
        var tempFileToDelete: URL?
        defer {
            if let url = tempFileToDelete {
                try? FileManager.default.removeItem(at: url)
            }
        }

        switch entry.captureMode {
        case .recording:
            let quality = settings.exportQuality
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            try await Task.detached(priority: .userInitiated) {
                try await Self.exportVideo(
                    from: sourceURL,
                    to: tmp,
                    format: .mp4,
                    exportQuality: quality
                )
            }.value
            uploadURL = tmp
            contentType = "video/mp4"
            tempFileToDelete = tmp
        case .gif:
            let quality = settings.exportQuality
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("gif")
            try await Task.detached(priority: .userInitiated) {
                try await Self.exportVideo(
                    from: sourceURL,
                    to: tmp,
                    format: .gif,
                    exportQuality: quality
                )
            }.value
            uploadURL = tmp
            contentType = "image/gif"
            tempFileToDelete = tmp
        default:
            uploadURL = sourceURL
            contentType = "image/png"
        }

        let cloudURL = try await coord.upload(file: uploadURL, contentType: contentType)
        setCloudURL(id: entry.id, url: cloudURL.absoluteString)
        return cloudURL
    }

    /// Delete the cloud copy for an entry using the last path component of its cloudURL as the key.
    /// Failure is silently swallowed — the local delete proceeds regardless.
    func deleteCloudCopy(for entry: HistoryEntry) async {
        guard let coord = shareCoordinator,
              let cloudURLString = entry.cloudURL,
              let key = URL(string: cloudURLString)?.lastPathComponent,
              !key.isEmpty else { return }
        do {
            try await coord.destination.delete(key: key)
        } catch {
            print("Cloud delete failed (proceeding with local delete): \(error)")
        }
    }

    // MARK: - Save Capture to History

    /// Save a capture result to history.
    /// - Parameter entryID: A pre-generated UUID so the caller can reference
    ///   this entry before the async save completes (e.g. to wire the cloud URL).
    /// - Returns: The UUID used for the new entry.
    @discardableResult
    func saveCapture(result: CaptureResult, entryID: UUID = UUID()) -> UUID {
        guard settings.historyEnabled, let store else { return entryID }

        let entryDir = store.entriesDirectory.appendingPathComponent(entryID.uuidString, isDirectory: true)
        let fm = FileManager.default

        Task.detached(priority: .utility) {
            do {
                try fm.createDirectory(at: entryDir, withIntermediateDirectories: true)

                // Save full image
                let fullImageName = "capture.png"
                let fullImageURL = entryDir.appendingPathComponent(fullImageName)
                let rep = NSBitmapImageRep(cgImage: result.image)
                guard let pngData = rep.representation(using: .png, properties: [:]) else { return }
                try pngData.write(to: fullImageURL)

                // Generate and save thumbnail
                let thumbName = "thumbnail.jpg"
                let thumbURL = entryDir.appendingPathComponent(thumbName)
                if let thumbData = ThumbnailGenerator.generateThumbnail(from: result.image) {
                    try thumbData.write(to: thumbURL)
                }

                let mode: HistoryCaptureMode = switch result.mode {
                case .area: .area
                case .fullscreen: .fullscreen
                case .window: .window
                case .scrolling: .area
                }

                let appName = result.appName
                    ?? NSWorkspace.shared.frontmostApplication?.localizedName

                let entry = HistoryEntry(
                    id: entryID,
                    captureMode: mode,
                    imageWidth: result.image.width,
                    imageHeight: result.image.height,
                    sourceAppName: appName,
                    sourceAppBundleID: result.appBundleIdentifier
                        ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                    sourceWindowTitle: result.windowName,
                    thumbnailFileName: thumbName,
                    fullImageFileName: fullImageName,
                    fileSize: Int64(pngData.count)
                )

                try store.insert(entry)

                await MainActor.run {
                    self.loadEntries()
                }
            } catch {
                print("Failed to save capture to history: \(error)")
            }
        }
        return entryID
    }

    // MARK: - Save Recording to History

    func saveRecording(url: URL, mode: HistoryCaptureMode) {
        guard settings.historyEnabled, let store else { return }

        let entryID = UUID()
        let entryDir = store.entriesDirectory.appendingPathComponent(entryID.uuidString, isDirectory: true)
        let fm = FileManager.default

        Task.detached(priority: .utility) {
            do {
                try fm.createDirectory(at: entryDir, withIntermediateDirectories: true)

                let fileName = url.lastPathComponent
                let destURL = entryDir.appendingPathComponent(fileName)
                try fm.copyItem(at: url, to: destURL)

                let fileSize = (try? fm.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0

                let thumbName = "thumbnail.jpg"
                let thumbURL = entryDir.appendingPathComponent(thumbName)
                if let thumbImage = await Self.extractFirstFrame(from: destURL),
                   let thumbData = ThumbnailGenerator.generateThumbnail(from: thumbImage) {
                    try thumbData.write(to: thumbURL)
                }

                let entry = HistoryEntry(
                    id: entryID,
                    captureMode: mode,
                    imageWidth: 0,
                    imageHeight: 0,
                    sourceAppName: NSWorkspace.shared.frontmostApplication?.localizedName,
                    sourceAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                    thumbnailFileName: thumbName,
                    fullImageFileName: fileName,
                    fileSize: fileSize
                )

                try store.insert(entry)
                await MainActor.run { self.loadEntries() }
            } catch {
                // Silently fail
            }
        }
    }

    private static func extractFirstFrame(from videoURL: URL) async -> CGImage? {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        do {
            let (image, _) = try await generator.image(at: .zero)
            return image
        } catch {
            return nil
        }
    }

    // MARK: - Actions

    func deleteEntry(_ entry: HistoryEntry) {
        guard let store else { return }
        do {
            try store.delete(id: entry.id)
            let entryDir = store.entriesDirectory.appendingPathComponent(entry.id.uuidString, isDirectory: true)
            try? FileManager.default.removeItem(at: entryDir)
            loadEntries()
        } catch {
            print("Failed to delete history entry: \(error)")
        }
    }

    func clearAll() {
        guard let store else { return }
        do {
            try HistoryCleanup.clearAll(store: store)
            loadEntries()
        } catch {
            print("Failed to clear history: \(error)")
        }
    }

    func fullImageURL(for entry: HistoryEntry) -> URL? {
        guard let store else { return nil }
        let url = store.entriesDirectory
            .appendingPathComponent(entry.id.uuidString, isDirectory: true)
            .appendingPathComponent(entry.fullImageFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func thumbnailURL(for entry: HistoryEntry) -> URL? {
        guard let store else { return nil }
        let url = store.entriesDirectory
            .appendingPathComponent(entry.id.uuidString, isDirectory: true)
            .appendingPathComponent(entry.thumbnailFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func loadFullImage(for entry: HistoryEntry) -> CGImage? {
        guard let url = fullImageURL(for: entry),
              let data = try? Data(contentsOf: url),
              let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                  pngDataProviderSource: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else { return nil }
        return image
    }

    func copyToClipboard(_ entry: HistoryEntry) {
        guard let sourceURL = fullImageURL(for: entry) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.captureMode {
        case .recording, .gif:
            pasteboard.writeObjects([sourceURL as NSURL])

        case .area, .fullscreen, .window:
            guard let nsImage = NSImage(contentsOf: sourceURL) else { return }
            pasteboard.writeObjects([nsImage])
        }
    }

    func saveToFile(_ entry: HistoryEntry) {
        guard let sourceURL = fullImageURL(for: entry) else { return }
        let fileFormat = preferredFileFormat(for: entry, sourceURL: sourceURL)
        let captureType = preferredCaptureType(for: entry)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = FileNaming.generateFileName(
            for: captureType,
            format: fileFormat,
            date: entry.createdAt
        )
        panel.allowedContentTypes = [fileFormat.contentType]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let destURL = panel.url {
            let exportQuality = settings.exportQuality
            Task.detached(priority: .utility) {
                do {
                    try await Self.writeHistoryEntry(
                        from: sourceURL,
                        to: destURL,
                        as: fileFormat,
                        exportQuality: exportQuality
                    )
                } catch {
                    print("Failed to save history entry to file: \(error)")
                }
            }
        }
    }

    func showInFinder(_ entry: HistoryEntry) {
        guard let url = fullImageURL(for: entry) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func preferredCaptureType(for entry: HistoryEntry) -> CaptureType {
        switch entry.captureMode {
        case .recording, .gif:
            return .recording
        case .area, .fullscreen, .window:
            return .screenshot
        }
    }

    private func preferredFileFormat(for entry: HistoryEntry, sourceURL: URL) -> FileFormat {
        switch entry.captureMode {
        case .gif:
            return .gif
        case .recording:
            return .mp4
        case .area, .fullscreen, .window:
            return FileFormat(pathExtension: sourceURL.pathExtension) ?? .png
        }
    }

    private static func writeHistoryEntry(
        from sourceURL: URL,
        to destinationURL: URL,
        as fileFormat: FileFormat,
        exportQuality: ExportQuality
    ) async throws {
        switch fileFormat {
        case .gif:
            if FileFormat(pathExtension: sourceURL.pathExtension) == .gif {
                try copyItemReplacingExisting(from: sourceURL, to: destinationURL)
            } else {
                try await exportVideo(from: sourceURL, to: destinationURL, format: .gif, exportQuality: exportQuality)
            }
        case .mp4:
            if FileFormat(pathExtension: sourceURL.pathExtension) == .mp4 {
                try copyItemReplacingExisting(from: sourceURL, to: destinationURL)
            } else {
                try await exportVideo(from: sourceURL, to: destinationURL, format: .mp4, exportQuality: exportQuality)
            }
        case .png, .jpeg, .mov:
            try copyItemReplacingExisting(from: sourceURL, to: destinationURL)
        }
    }

    private static func exportVideo(
        from sourceURL: URL,
        to destinationURL: URL,
        format: ExportFormat,
        exportQuality: ExportQuality
    ) async throws {
        try removeExistingItemIfNeeded(at: destinationURL)
        _ = try await VideoExporter.export(
            source: sourceURL,
            options: ExportOptions(
                format: format,
                quality: exportQuality,
                destination: destinationURL
            )
        )
    }

    private static func copyItemReplacingExisting(from sourceURL: URL, to destinationURL: URL) throws {
        try removeExistingItemIfNeeded(at: destinationURL)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func removeExistingItemIfNeeded(at url: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func runCleanup() {
        guard let store else { return }
        let retention = HistoryRetention(rawValue: settings.historyRetention) ?? .oneMonth
        do {
            let removed = try HistoryCleanup.enforce(store: store, retention: retention)
            if removed > 0 {
                print("History cleanup: removed \(removed) expired entries")
                loadEntries()
            }
        } catch {
            print("History cleanup failed: \(error)")
        }
    }

    func entryCount(for filter: HistoryFilter) -> Int {
        guard let store else { return 0 }
        return (try? store.count(filter: filter)) ?? 0
    }
}
