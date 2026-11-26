// App/Sources/History/HistoryCoordinator.swift
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import Observation
import PDFKit
import CaptureKit
import ExportKit
import HistoryKit
import ShareKit
import SharedKit

@MainActor
@Observable
final class HistoryCoordinator {
    struct PDFImportProgress: Equatable {
        let fileName: String
        let completedPages: Int
        let totalPages: Int

        var fraction: Double {
            guard totalPages > 0 else { return 0 }
            return Double(completedPages) / Double(totalPages)
        }
    }

    private enum HistorySaveError: Error {
        case pngEncodingFailed
    }

    let settings: AppSettings
    private let store: HistoryStore?
    private(set) var entries: [HistoryEntry] = []
    private(set) var collections: [HistoryCollectionSummary] = []
    private(set) var activeCollectionID: UUID?
    private(set) var activeCollectionEntries: [HistoryEntry] = []
    private(set) var pdfImportProgress: PDFImportProgress?
    private(set) var pdfImportError: String?
    private(set) var totalSize: Int64 = 0
    var currentFilter: HistoryFilter = .all
    /// Cloud sharing coordinator — set by AppDelegate after creation.
    /// Non-nil only when cloud sharing is configured.
    var shareCoordinator: ShareCoordinator?
    /// Opens a recording from history in the video editor.
    var onEditRecording: ((HistoryRecordingSource) -> Void)?

    private var historyWindow: HistoryWindow?
    private var annotationWindow: AnnotationEditorWindow?
    private var pinnedControllers: [PinnedScreenshotController] = []
    private let dragFileStore = QuickAccessDragFileStore()
    private var dragFileURLs: [UUID: URL] = [:]
    private var dragPreparationTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingCloudURLs = PendingHistoryCloudURLTracker()
    private var pdfImportTask: Task<Void, Never>?

    init(settings: AppSettings, store: HistoryStore? = nil) {
        self.settings = settings
        self.store = store ?? (try? HistoryStore())
    }

    var activeCollection: HistoryCollectionSummary? {
        guard let activeCollectionID else { return nil }
        return collections.first { $0.id == activeCollectionID }
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

    func toggleWindow() {
        if let historyWindow {
            historyWindow.toggle()
            return
        }
        showWindow()
    }

#if DEBUG
    var isWindowVisibleForTesting: Bool {
        historyWindow?.isVisibleForTesting == true
    }
#endif

    // MARK: - Data Loading

    func loadEntries() {
        guard let store else { return }
        persistHeldCloudURLs(using: store)
        do {
            entries = try store.fetchAll(filter: currentFilter)
            collections = try store.fetchCollectionSummaries()
            if let activeCollectionID {
                if collections.contains(where: { $0.id == activeCollectionID }) {
                    activeCollectionEntries = try store.fetchCollectionEntries(collectionID: activeCollectionID)
                } else {
                    self.activeCollectionID = nil
                    activeCollectionEntries = []
                }
            } else {
                activeCollectionEntries = []
            }
            totalSize = try store.totalFileSize()
        } catch {
            print("Failed to load history: \(error)")
        }
    }

    func setFilter(_ filter: HistoryFilter) {
        currentFilter = filter
        loadEntries()
    }

    /// Returns all regular screenshots in history (used by the "Add Screenshots to Deck" picker).
    func availableScreenshots() -> [HistoryEntry] {
        guard let store else { return [] }
        return (try? store.fetchAll(filter: .screenshots)) ?? []
    }

    // MARK: - PDF Collections

    func openCollection(_ id: UUID) {
        activeCollectionID = id
        loadEntries()
    }

    func closeCollection() {
        activeCollectionID = nil
        activeCollectionEntries = []
    }

    func dismissPDFImportError() {
        pdfImportError = nil
    }

    func renameCollection(_ id: UUID, to title: String) {
        guard let store else { return }
        do {
            try store.renameCollection(id: id, title: title)
            loadEntries()
        } catch {
            print("Failed to rename collection: \(error)")
        }
    }

    func deleteCollection(_ id: UUID) {
        guard let store else { return }
        do {
            let orphanedPages = try store.deleteCollection(id: id)
            removeEntryDirectories(for: orphanedPages, in: store)
            if activeCollectionID == id {
                activeCollectionID = nil
                activeCollectionEntries = []
            }
            loadEntries()
        } catch {
            print("Failed to delete collection: \(error)")
        }
    }

    func addEntries(_ entries: [HistoryEntry], toCollection collectionID: UUID, insertAt index: Int? = nil) {
        guard let store else { return }
        let screenshotIDs = entries.filter { isScreenshot($0) }.map(\.id)
        guard !screenshotIDs.isEmpty else { return }
        do {
            try store.addEntries(screenshotIDs, toCollection: collectionID, insertAt: index)
            loadEntries()
        } catch {
            print("Failed to add entries to collection: \(error)")
        }
    }

    func reorderCollection(_ collectionID: UUID, orderedEntryIDs: [UUID]) {
        guard let store else { return }
        do {
            try store.reorderCollection(collectionID: collectionID, orderedEntryIDs: orderedEntryIDs)
            loadEntries()
        } catch {
            print("Failed to reorder collection: \(error)")
        }
    }

    func moveEntry(
        _ entryID: UUID,
        before targetEntryID: UUID,
        inCollection collectionID: UUID
    ) {
        guard entryID != targetEntryID else { return }
        var ids = (try? store?.fetchCollectionEntries(collectionID: collectionID).map(\.id)) ?? []
        guard let sourceIndex = ids.firstIndex(of: entryID),
              let targetIndex = ids.firstIndex(of: targetEntryID) else { return }
        ids.remove(at: sourceIndex)
        ids.insert(entryID, at: targetIndex)
        reorderCollection(collectionID, orderedEntryIDs: ids)
    }

    func moveEntry(
        _ entryID: UUID,
        by offset: Int,
        inCollection collectionID: UUID
    ) {
        var ids = (try? store?.fetchCollectionEntries(collectionID: collectionID).map(\.id)) ?? []
        guard let sourceIndex = ids.firstIndex(of: entryID) else { return }
        let targetIndex = max(0, min(ids.count - 1, sourceIndex + offset))
        guard targetIndex != sourceIndex else { return }
        ids.remove(at: sourceIndex)
        ids.insert(entryID, at: targetIndex)
        reorderCollection(collectionID, orderedEntryIDs: ids)
    }

    func removeEntries(_ entries: [HistoryEntry], fromCollection collectionID: UUID) {
        guard let store, !entries.isEmpty else { return }
        do {
            let orphanedPages = try store.removeEntries(entries.map(\.id), fromCollection: collectionID)
            removeEntryDirectories(for: orphanedPages, in: store)
            loadEntries()
        } catch {
            print("Failed to remove entries from collection: \(error)")
        }
    }

    @discardableResult
    func pasteImageIntoCollection(_ collectionID: UUID, insertAt index: Int? = nil) -> Bool {
        guard let cgImage = ClipboardImageReader.image(from: .general) else { return false }
        addImage(cgImage, displayName: String(localized: "Pasted Image"), toCollection: collectionID, insertAt: index)
        return true
    }

    func addImageFiles(_ urls: [URL], toCollection collectionID: UUID, insertAt index: Int? = nil) {
        let supported = urls.filter { ImageFileReader.isSupported($0) }
        guard !supported.isEmpty else { return }
        var currentIndex = index
        for url in supported {
            guard let cgImage = ImageFileReader.image(at: url) else { continue }
            let title = url.deletingPathExtension().lastPathComponent
            addImage(cgImage, displayName: title, toCollection: collectionID, insertAt: currentIndex)
            if let idx = currentIndex {
                currentIndex = idx + 1
            }
        }
    }

    func addImage(_ image: CGImage, displayName: String, toCollection collectionID: UUID, insertAt index: Int? = nil) {
        guard let store else { return }
        let entryID = UUID()
        let entryDir = store.entriesDirectory.appendingPathComponent(entryID.uuidString, isDirectory: true)
        Task.detached(priority: .userInitiated) {
            do {
                try FileManager.default.createDirectory(at: entryDir, withIntermediateDirectories: true)
                let fullImageName = "capture.png"
                let fullImageURL = entryDir.appendingPathComponent(fullImageName)
                guard let pngData = ImageUtilities.pngData(from: image) else {
                    throw HistorySaveError.pngEncodingFailed
                }
                try pngData.write(to: fullImageURL, options: [.atomic])

                let thumbName = "thumbnail.jpg"
                let thumbURL = entryDir.appendingPathComponent(thumbName)
                if let thumbData = ThumbnailGenerator.generateThumbnail(from: image) {
                    try thumbData.write(to: thumbURL, options: [.atomic])
                }

                let entry = HistoryEntry(
                    id: entryID,
                    captureMode: .pdfPage,
                    imageWidth: image.width,
                    imageHeight: image.height,
                    sourceAppName: displayName,
                    thumbnailFileName: thumbName,
                    fullImageFileName: fullImageName,
                    fileSize: Int64(pngData.count)
                )
                try store.insertEntryAndAddToCollection(entry, collectionID: collectionID, insertAt: index)
                await MainActor.run { self.loadEntries() }
            } catch {
                try? FileManager.default.removeItem(at: entryDir)
                print("Failed to add image to collection: \(error)")
            }
        }
    }

    func importPDFWithPanel(intoCollectionID: UUID? = nil, insertAt index: Int? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = String(localized: "Import PDF")
        panel.prompt = String(localized: "Import")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        importPDFFiles(panel.urls, openHistoryWindow: false, intoCollectionID: intoCollectionID, insertAt: index)
    }

    func importPDFFiles(
        _ urls: [URL],
        openHistoryWindow: Bool = false,
        intoCollectionID: UUID? = nil,
        insertAt index: Int? = nil
    ) {
        let pdfURLs = urls.filter { $0.isFileURL && $0.pathExtension.lowercased() == "pdf" }
        guard !pdfURLs.isEmpty else { return }
        if openHistoryWindow {
            showWindow()
        }

        pdfImportTask?.cancel()
        pdfImportError = nil
        pdfImportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var currentInsertIndex = index
            var lastCreatedCollectionID: UUID?
            for url in pdfURLs {
                if Task.isCancelled { break }
                if let collectionID = await self.importPDF(
                    from: url,
                    intoCollectionID: intoCollectionID,
                    insertAt: currentInsertIndex
                ) {
                    lastCreatedCollectionID = collectionID
                    if let idx = currentInsertIndex, let count = PDFDocument(url: url)?.pageCount {
                        currentInsertIndex = idx + count
                    }
                }
            }
            self.pdfImportProgress = nil
            self.pdfImportTask = nil
            if let lastCreatedCollectionID, intoCollectionID == nil {
                self.openCollection(lastCreatedCollectionID)
            }
        }
    }

    func cancelPDFImport() {
        pdfImportTask?.cancel()
        pdfImportTask = nil
        pdfImportProgress = nil
    }

    /// Imports every page of `url` into a new collection (or into `intoCollectionID` when provided).
    /// Returns the target collection ID on success.
    @discardableResult
    func importPDF(
        from url: URL,
        intoCollectionID: UUID? = nil,
        insertAt index: Int? = nil,
        password: String? = nil
    ) async -> UUID? {
        guard let store else { return nil }
        guard let document = PDFDocument(url: url) else {
            pdfImportError = String(localized: "Could not open PDF file \"\(url.lastPathComponent)\".")
            return nil
        }

        let resolvedPassword: String?
        if document.isLocked {
            if let password {
                resolvedPassword = password
            } else if let prompted = promptForPDFPassword(fileName: url.lastPathComponent) {
                resolvedPassword = prompted
            } else {
                return nil
            }
            guard let resolvedPassword, document.unlock(withPassword: resolvedPassword) else {
                pdfImportError = String(localized: "Incorrect password for \"\(url.lastPathComponent)\".")
                return nil
            }
        } else {
            resolvedPassword = nil
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else {
            pdfImportError = String(localized: "PDF file \"\(url.lastPathComponent)\" has no pages.")
            return nil
        }

        let title = url.deletingPathExtension().lastPathComponent
        let collectionID: UUID
        let createdNewCollection: Bool
        if let intoCollectionID {
            collectionID = intoCollectionID
            createdNewCollection = false
        } else {
            let collection = HistoryCollection(title: title)
            do {
                try store.createCollection(collection)
                collectionID = collection.id
                createdNewCollection = true
            } catch {
                pdfImportError = error.localizedDescription
                return nil
            }
        }

        let fileName = url.lastPathComponent
        pdfImportProgress = PDFImportProgress(fileName: fileName, completedPages: 0, totalPages: pageCount)
        loadEntries()

        let entriesDirectory = store.entriesDirectory
        var importedAnyPage = false

        for pageIndex in 0..<pageCount {
            if Task.isCancelled { break }
            let targetInsertIndex = index.map { $0 + pageIndex }
            let renderedSuccess: Bool = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    guard let doc = PDFDocument(url: url) else { return false }
                    if doc.isLocked, let resolvedPassword {
                        guard doc.unlock(withPassword: resolvedPassword) else { return false }
                    }
                    guard let page = doc.page(at: pageIndex),
                          let image = Self.renderPDFPage(page),
                          let pngData = ImageUtilities.pngData(from: image) else {
                        return false
                    }

                    let entryID = UUID()
                    let entryDir = entriesDirectory.appendingPathComponent(entryID.uuidString, isDirectory: true)
                    do {
                        try FileManager.default.createDirectory(at: entryDir, withIntermediateDirectories: true)
                        let fullImageName = "capture.png"
                        try pngData.write(to: entryDir.appendingPathComponent(fullImageName), options: [.atomic])

                        let thumbName = "thumbnail.jpg"
                        if let thumbData = ThumbnailGenerator.generateThumbnail(from: image) {
                            try thumbData.write(to: entryDir.appendingPathComponent(thumbName), options: [.atomic])
                        }

                        let entry = HistoryEntry(
                            id: entryID,
                            captureMode: .pdfPage,
                            imageWidth: image.width,
                            imageHeight: image.height,
                            sourceAppName: title,
                            sourceWindowTitle: String(localized: "Page \(pageIndex + 1)"),
                            thumbnailFileName: thumbName,
                            fullImageFileName: fullImageName,
                            fileSize: Int64(pngData.count)
                        )
                        try store.insertEntryAndAddToCollection(
                            entry,
                            collectionID: collectionID,
                            insertAt: targetInsertIndex
                        )
                        return true
                    } catch {
                        try? FileManager.default.removeItem(at: entryDir)
                        return false
                    }
                }
            }.value

            if renderedSuccess {
                importedAnyPage = true
            }
            pdfImportProgress = PDFImportProgress(
                fileName: fileName,
                completedPages: pageIndex + 1,
                totalPages: pageCount
            )
            if pageIndex == 0 || (pageIndex + 1) % 5 == 0 || pageIndex + 1 == pageCount {
                loadEntries()
            }
        }

        if !importedAnyPage, createdNewCollection {
            _ = try? store.deleteCollection(id: collectionID)
            loadEntries()
            return nil
        }

        loadEntries()
        return collectionID
    }

    /// Renders a PDF page onto an opaque white sRGB bitmap suitable for annotation.
    nonisolated static func renderPDFPage(
        _ page: PDFPage,
        scale: CGFloat = 2.0,
        maxDimension: CGFloat = 2400
    ) -> CGImage? {
        let cropBounds = page.bounds(for: .cropBox)
        let rawBounds = cropBounds.isEmpty ? page.bounds(for: .mediaBox) : cropBounds
        guard rawBounds.width > 0, rawBounds.height > 0 else { return nil }

        let rotation = ((page.rotation % 360) + 360) % 360
        let rotatedSize = (rotation == 90 || rotation == 270)
            ? CGSize(width: rawBounds.height, height: rawBounds.width)
            : rawBounds.size

        let longest = max(rotatedSize.width, rotatedSize.height)
        let effectiveScale = min(scale, maxDimension / longest)
        let pixelWidth = max(1, Int((rotatedSize.width * effectiveScale).rounded()))
        let pixelHeight = max(1, Int((rotatedSize.height * effectiveScale).rounded()))

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.interpolationQuality = .high
        ctx.scaleBy(
            x: CGFloat(pixelWidth) / rotatedSize.width,
            y: CGFloat(pixelHeight) / rotatedSize.height
        )
        let box: PDFDisplayBox = cropBounds.isEmpty ? .mediaBox : .cropBox
        let transform = page.transform(for: box)
        ctx.concatenate(transform)
        page.draw(with: box, to: ctx)
        return ctx.makeImage()
    }

    private func promptForPDFPassword(fileName: String) -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Password Required")
        alert.informativeText = String(localized: "Enter the password to unlock \"\(fileName)\".")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Unlock"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private func removeEntryDirectories(for entries: [HistoryEntry], in store: HistoryStore) {
        let fm = FileManager.default
        for entry in entries {
            let entryDir = store.entriesDirectory.appendingPathComponent(entry.id.uuidString, isDirectory: true)
            try? fm.removeItem(at: entryDir)
            clearDragFileCache(for: entry)
        }
    }

    // MARK: - Cloud URL

    /// Persist the cloud-share URL for a history entry after a successful upload.
    /// Can be called from any context (e.g. QuickAccess upload callback).
    func setCloudURL(id: UUID, url: String) {
        guard let store else { return }
        do {
            if try store.setCloudURL(id: id, url: url) {
                pendingCloudURLs.completePersistence(id: id)
                // Refresh in-memory list so the History UI reflects the change.
                loadEntries()
            } else if pendingCloudURLs.hold(url: url, for: id) {
                // A fast upload can finish before the detached history insert.
                // Hold the URL until that specific insert completes.
            }
        } catch {
            _ = pendingCloudURLs.hold(url: url, for: id)
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
    /// upload as-is in their stored format.
    func uploadEntry(_ entry: HistoryEntry) async throws -> URL {
        guard let coord = shareCoordinator else {
            throw ShareError.notConfigured
        }
        guard let sourceURL = fullImageURL(for: entry) else {
            throw ShareError.unknown("Source file not found")
        }

        let prepared = try await prepareUpload(sourceURL: sourceURL, mode: entry.captureMode)
        defer { prepared.removeTemporaryFile() }

        let cloudURL = try await coord.upload(file: prepared.url, contentType: prepared.contentType)
        setCloudURL(id: entry.id, url: cloudURL.absoluteString)
        return cloudURL
    }

    /// Upload a just-completed recording without waiting for its asynchronous
    /// history insert. The pending-entry bridge above persists the URL once the
    /// row exists, while history-disabled users still get the share link.
    func uploadRecording(url: URL, mode: HistoryCaptureMode, entryID: UUID) async throws -> URL {
        guard let coord = shareCoordinator else {
            throw ShareError.notConfigured
        }

        let prepared = try await prepareUpload(sourceURL: url, mode: mode)
        defer { prepared.removeTemporaryFile() }

        let cloudURL = try await coord.upload(file: prepared.url, contentType: prepared.contentType)
        setCloudURL(id: entryID, url: cloudURL.absoluteString)
        return cloudURL
    }

    private struct PreparedUpload {
        let url: URL
        let contentType: String
        let temporaryURL: URL?

        func removeTemporaryFile() {
            if let temporaryURL {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }
    }

    private func prepareUpload(sourceURL: URL, mode: HistoryCaptureMode) async throws -> PreparedUpload {
        let format: ExportFormat
        let fileExtension: String
        let contentType: String

        switch mode {
        case .recording:
            format = .mp4
            fileExtension = "mp4"
            contentType = "video/mp4"
        case .gif:
            format = .gif
            fileExtension = "gif"
            contentType = "image/gif"
        case .area, .fullscreen, .window, .pdfPage:
            let type = UTType(filenameExtension: sourceURL.pathExtension.lowercased())
            return PreparedUpload(
                url: sourceURL,
                contentType: type?.preferredMIMEType ?? "image/png",
                temporaryURL: nil
            )
        }

        let quality = settings.exportQuality
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try await Task.detached(priority: .userInitiated) {
            try await Self.exportVideo(
                from: sourceURL,
                to: temporaryURL,
                format: format,
                exportQuality: quality
            )
        }.value
        return PreparedUpload(
            url: temporaryURL,
            contentType: contentType,
            temporaryURL: temporaryURL
        )
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

        pendingCloudURLs.begin(id: entryID)
        let entryDir = store.entriesDirectory.appendingPathComponent(entryID.uuidString, isDirectory: true)
        let fm = FileManager.default

        Task.detached(priority: .utility) {
            do {
                try fm.createDirectory(at: entryDir, withIntermediateDirectories: true)

                // Save full image
                let fullImageName = "capture.png"
                let fullImageURL = entryDir.appendingPathComponent(fullImageName)
                let rep = NSBitmapImageRep(cgImage: result.image)
                guard let pngData = rep.representation(using: .png, properties: [:]) else {
                    throw HistorySaveError.pngEncodingFailed
                }
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

                await MainActor.run { self.finishPendingHistoryInsert(id: entryID) }
            } catch {
                print("Failed to save capture to history: \(error)")
                await MainActor.run { self.cancelPendingHistoryInsert(id: entryID) }
            }
        }
        return entryID
    }

    // MARK: - Save Recording to History

    @discardableResult
    func saveRecording(
        url: URL,
        mode: HistoryCaptureMode,
        entryID: UUID = UUID(),
        cursorTelemetryURL: URL? = nil,
        info: HistoryRecordingInfo? = nil
    ) -> UUID {
        guard settings.historyEnabled, let store else { return entryID }

        pendingCloudURLs.begin(id: entryID)
        let entryDir = store.entriesDirectory.appendingPathComponent(entryID.uuidString, isDirectory: true)
        let fm = FileManager.default

        Task.detached(priority: .utility) {
            do {
                try fm.createDirectory(at: entryDir, withIntermediateDirectories: true)

                let fileName = url.lastPathComponent
                let destURL = entryDir.appendingPathComponent(fileName)
                try fm.copyItem(at: url, to: destURL)

                let fileSize = (try? fm.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0
                if let cursorTelemetryURL {
                    try? fm.copyItem(at: cursorTelemetryURL, to: entryDir.appendingPathComponent(HistoryRecordingSource.cursorFileName))
                }
                if let info, let data = try? JSONEncoder().encode(info) {
                    try? data.write(to: entryDir.appendingPathComponent(HistoryRecordingSource.infoFileName))
                }

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
                await MainActor.run { self.finishPendingHistoryInsert(id: entryID) }
            } catch {
                await MainActor.run { self.cancelPendingHistoryInsert(id: entryID) }
            }
        }
        return entryID
    }

    private func finishPendingHistoryInsert(id: UUID) {
        _ = pendingCloudURLs.finish(id: id)
        loadEntries()
    }

    private func cancelPendingHistoryInsert(id: UUID) {
        pendingCloudURLs.cancel(id: id)
    }

    private func persistHeldCloudURLs(using store: HistoryStore) {
        for (id, cloudURL) in pendingCloudURLs.heldURLsForPersistence {
            do {
                if try store.setCloudURL(id: id, url: cloudURL) {
                    pendingCloudURLs.completePersistence(id: id)
                }
            } catch {
                // Keep the URL in the tracker so a later load can retry.
                print("Failed to persist pending cloud URL: \(error)")
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
            clearDragFileCache(for: entry)
            loadEntries()
        } catch {
            print("Failed to delete history entry: \(error)")
        }
    }

    func clearAll() {
        guard let store else { return }
        do {
            try HistoryCleanup.clearAll(store: store)
            clearDragFileCaches()
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
        guard let url = fullImageURL(for: entry) else { return nil }
        return Self.loadCGImage(from: url)
    }

    func prepareDragFile(for entry: HistoryEntry) {
        guard isScreenshot(entry) else { return }
        if let cachedURL = dragFileURLs[entry.id] {
            if FileManager.default.isReadableFile(atPath: cachedURL.path) {
                return
            }
            dragFileURLs[entry.id] = nil
        }

        guard dragFileURLs[entry.id] == nil,
              dragPreparationTasks[entry.id] == nil,
              let fullURL = fullImageURL(for: entry) else { return }

        let id = entry.id
        let output = settings.screenshotOutputOptions
        let date = entry.createdAt
        let sourceAppName = entry.sourceAppName
        let sourceWindowTitle = entry.sourceWindowTitle
        let template = settings.screenshotFilenameTemplate

        dragPreparationTasks[id] = Task { [weak self] in
            let preparedURL = await Task.detached(priority: .utility) { () -> URL? in
                guard let image = Self.loadCGImage(from: fullURL) else { return nil }
                let store = QuickAccessDragFileStore()
                return try? store.fileURL(
                    for: image,
                    id: id,
                    output: output,
                    date: date,
                    sourceAppName: sourceAppName,
                    sourceWindowTitle: sourceWindowTitle,
                    template: template
                )
            }.value
            let wasCancelled = Task.isCancelled

            await MainActor.run {
                guard let self else {
                    if let preparedURL {
                        try? FileManager.default.removeItem(at: preparedURL)
                    }
                    return
                }

                self.dragPreparationTasks[id] = nil
                guard let preparedURL else { return }
                if wasCancelled || self.dragFileURLs[id] != nil {
                    try? FileManager.default.removeItem(at: preparedURL)
                    return
                }
                self.dragFileURLs[id] = preparedURL
            }
        }
    }

    func dragFileURL(for entry: HistoryEntry) -> URL? {
        guard isScreenshot(entry) else { return nil }
        if let cachedURL = dragFileURLs[entry.id] {
            if FileManager.default.isReadableFile(atPath: cachedURL.path) {
                return cachedURL
            }
            dragFileURLs[entry.id] = nil
        }

        dragPreparationTasks[entry.id]?.cancel()
        dragPreparationTasks[entry.id] = nil

        guard let image = loadFullImage(for: entry) else { return nil }

        do {
            let fileURL = try dragFileStore.fileURL(
                for: image,
                id: entry.id,
                output: settings.screenshotOutputOptions,
                date: entry.createdAt,
                sourceAppName: entry.sourceAppName,
                sourceWindowTitle: entry.sourceWindowTitle,
                template: settings.screenshotFilenameTemplate
            )
            dragFileURLs[entry.id] = fileURL
            return fileURL
        } catch {
            return nil
        }
    }

    func editEntry(_ entry: HistoryEntry) {
        if !isScreenshot(entry) {
            if let videoURL = fullImageURL(for: entry) {
                onEditRecording?(HistoryRecordingSource(entry: entry, videoURL: videoURL))
            }
            return
        }
        guard let image = loadFullImage(for: entry) else { return }

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main

        annotationWindow?.close()
        annotationWindow = nil
        let window = AnnotationEditorWindow(
            image: image,
            anchorScreen: screen,
            sourceAppName: entry.sourceAppName,
            sourceWindowTitle: entry.sourceWindowTitle,
            captureDate: entry.createdAt,
            screenshotOutput: settings.screenshotOutputOptions,
            screenshotFilenameTemplate: settings.screenshotFilenameTemplate,
            onSave: { [weak self] rendered in
                self?.replaceImage(for: entry, with: rendered)
                self?.annotationWindow = nil
                return true
            },
            onCopy: { [weak self] rendered in
                self?.copyScreenshotToClipboard(rendered)
                self?.annotationWindow = nil
            },
            onPin: { [weak self] rendered, frame in
                self?.pinImage(
                    rendered,
                    anchor: frame,
                    sourceAppName: entry.sourceAppName,
                    sourceWindowTitle: entry.sourceWindowTitle,
                    date: entry.createdAt
                )
                self?.annotationWindow = nil
            },
            onClose: { [weak self] in
                self?.annotationWindow = nil
            }
        )
        annotationWindow = window
        window.show()
    }

    private func replaceImage(for entry: HistoryEntry, with image: CGImage) {
        guard isScreenshot(entry),
              let store,
              let fullURL = fullImageURL(for: entry),
              let thumbnailURL = thumbnailURL(for: entry) else { return }

        Task.detached(priority: .utility) {
            guard let pngData = ImageUtilities.pngData(from: image) else { return }
            do {
                try pngData.write(to: fullURL, options: [.atomic])
                if let thumbnailData = ThumbnailGenerator.generateThumbnail(from: image) {
                    try thumbnailData.write(to: thumbnailURL, options: [.atomic])
                }

                let updated = HistoryEntry(
                    id: entry.id,
                    createdAt: entry.createdAt,
                    captureMode: entry.captureMode,
                    imageWidth: image.width,
                    imageHeight: image.height,
                    sourceAppName: entry.sourceAppName,
                    sourceAppBundleID: entry.sourceAppBundleID,
                    sourceWindowTitle: entry.sourceWindowTitle,
                    thumbnailFileName: entry.thumbnailFileName,
                    fullImageFileName: entry.fullImageFileName,
                    annotationFileName: entry.annotationFileName,
                    fileSize: Int64(pngData.count),
                    // The edited bitmap no longer matches any existing uploaded object.
                    cloudURL: nil
                )
                try store.update(updated)
                await MainActor.run {
                    self.clearDragFileCache(for: entry)
                    self.loadEntries()
                }
            } catch {
                return
            }
        }
    }

    private func isScreenshot(_ entry: HistoryEntry) -> Bool {
        switch entry.captureMode {
        case .area, .fullscreen, .window, .pdfPage:
            return true
        case .recording, .gif:
            return false
        }
    }

    nonisolated private static func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func clearDragFileCache(for entry: HistoryEntry) {
        clearDragFileCache(for: entry.id)
    }

    private func clearDragFileCache(for id: UUID) {
        dragPreparationTasks[id]?.cancel()
        dragPreparationTasks[id] = nil
        if let fileURL = dragFileURLs.removeValue(forKey: id) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        try? dragFileStore.removeFile(for: id)
    }

    private func clearDragFileCaches() {
        for task in dragPreparationTasks.values {
            task.cancel()
        }
        dragPreparationTasks.removeAll()
        for fileURL in dragFileURLs.values {
            try? FileManager.default.removeItem(at: fileURL)
        }
        dragFileURLs.removeAll()
    }

    @discardableResult
    func copyScreenshotToClipboard(
        _ image: CGImage,
        preferredFileURL: URL? = nil,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        let temporaryFileStore = QuickAccessDragFileStore()
        return ScreenshotClipboard.copy(
            image,
            content: settings.screenshotClipboardContent,
            imageFormat: settings.screenshotClipboardFormat,
            pasteboard: pasteboard
        ) {
            if let preferredFileURL,
               FileManager.default.isReadableFile(atPath: preferredFileURL.path) {
                return preferredFileURL
            }
            return try temporaryFileStore.fileURL(
                for: image,
                id: UUID(),
                output: self.settings.screenshotOutputOptions,
                template: self.settings.screenshotFilenameTemplate
            )
        }
    }

    private func pinImage(
        _ image: CGImage,
        anchor: CGRect?,
        sourceAppName: String?,
        sourceWindowTitle: String?,
        date: Date
    ) {
        let controller = PinnedScreenshotController(
            image: image,
            anchorRect: anchor,
            onCopy: { [weak self] in
                self?.copyScreenshotToClipboard(image)
            },
            onSave: { [weak self] in
                self?.saveImageToExportLocation(
                    image,
                    sourceAppName: sourceAppName,
                    sourceWindowTitle: sourceWindowTitle,
                    date: date
                )
            },
            onDidClose: { [weak self] controllerID in
                self?.pinnedControllers.removeAll { $0.id == controllerID }
            }
        )
        pinnedControllers.append(controller)
        controller.show()
    }

    private func saveImageToExportLocation(
        _ image: CGImage,
        sourceAppName: String?,
        sourceWindowTitle: String?,
        date: Date
    ) {
        let output = settings.screenshotOutputOptions
        guard let data = ImageEncoders.default.encode(
            image, format: output.format, quality: output.quality
        ) else { return }

        let directory = settings.screenshotMonthlyFolders
            ? FileNaming.monthlyDirectory(in: settings.exportLocation)
            : settings.exportLocation
        let url = FileNaming.generateFileURL(
            in: directory,
            type: .screenshot,
            format: output.format.fileFormat,
            date: date,
            sourceAppName: sourceAppName,
            sourceWindowTitle: sourceWindowTitle,
            template: settings.screenshotFilenameTemplate
        )
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    func copyToClipboard(_ entry: HistoryEntry) {
        guard let sourceURL = fullImageURL(for: entry) else { return }

        switch entry.captureMode {
        case .recording, .gif:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([sourceURL as NSURL])

        case .area, .fullscreen, .window, .pdfPage:
            guard let image = Self.loadCGImage(from: sourceURL) else { return }
            copyScreenshotToClipboard(image, preferredFileURL: sourceURL)
        }
    }

    func saveToFile(_ entry: HistoryEntry) {
        guard let sourceURL = fullImageURL(for: entry) else { return }
        let fileFormat = preferredFileFormat(for: entry, sourceURL: sourceURL)
        let captureType = preferredCaptureType(for: entry)
        let sourceAppName: String? = switch captureType {
        case .screenshot:
            entry.sourceAppName
        case .recording:
            nil
        }
        let sourceWindowTitle: String? = switch captureType {
        case .screenshot:
            entry.sourceWindowTitle
        case .recording:
            nil
        }
        let filenameTemplate: String? = switch captureType {
        case .screenshot:
            settings.screenshotFilenameTemplate
        case .recording:
            nil
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = FileNaming.generateFileName(
            for: captureType,
            format: fileFormat,
            date: entry.createdAt,
            sourceAppName: sourceAppName,
            sourceWindowTitle: sourceWindowTitle,
            template: filenameTemplate
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

    /// Combines the screenshots among `entries` into one PDF, one capture per page.
    /// By default sorts oldest-first (for chronological history groups); pass `preserveOrder: true`
    /// for ordered PDF collections.
    func exportAsPDF(
        _ entries: [HistoryEntry],
        preserveOrder: Bool = false,
        defaultFileName: String? = nil
    ) {
        let filtered = entries.filter { preferredCaptureType(for: $0) == .screenshot }
        let screenshots = preserveOrder ? filtered : filtered.sorted { $0.createdAt < $1.createdAt }
        let imageURLs = screenshots.compactMap { fullImageURL(for: $0) }
        guard let first = screenshots.first, !imageURLs.isEmpty else { return }

        let panel = NSSavePanel()
        if let defaultFileName, !defaultFileName.isEmpty {
            panel.nameFieldStringValue = defaultFileName.lowercased().hasSuffix(".pdf")
                ? defaultFileName
                : "\(defaultFileName).pdf"
        } else {
            panel.nameFieldStringValue = "Capso \(first.createdAt.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())).pdf"
        }
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        Task.detached(priority: .utility) {
            if !Self.writePDF(pages: imageURLs, to: destURL) {
                print("Failed to export history as PDF")
            }
        }
    }

    func exportCollectionAsPDF(_ collection: HistoryCollection) {
        guard let store,
              let entries = try? store.fetchCollectionEntries(collectionID: collection.id),
              !entries.isEmpty else { return }
        exportAsPDF(entries, preserveOrder: true, defaultFileName: collection.title)
    }

    /// Writes `collection`'s ordered pages directly to `destinationURL`. Used by export and tests.
    @discardableResult
    func writeCollectionPDF(_ collectionID: UUID, to destinationURL: URL) -> Bool {
        guard let store,
              let entries = try? store.fetchCollectionEntries(collectionID: collectionID) else {
            return false
        }
        let urls = entries.compactMap { fullImageURL(for: $0) }
        return Self.writePDF(pages: urls, to: destinationURL)
    }

    nonisolated static func writePDF(pages imageURLs: [URL], to destinationURL: URL) -> Bool {
        let document = PDFDocument()
        for url in imageURLs {
            guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else { continue }
            document.insert(page, at: document.pageCount)
        }
        return document.pageCount > 0 && document.write(to: destinationURL)
    }

    func showInFinder(_ entry: HistoryEntry) {
        guard let url = fullImageURL(for: entry) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func preferredCaptureType(for entry: HistoryEntry) -> CaptureType {
        switch entry.captureMode {
        case .recording, .gif:
            return .recording
        case .area, .fullscreen, .window, .pdfPage:
            return .screenshot
        }
    }

    private func preferredFileFormat(for entry: HistoryEntry, sourceURL: URL) -> FileFormat {
        switch entry.captureMode {
        case .gif:
            return .gif
        case .recording:
            return .mp4
        case .area, .fullscreen, .window, .pdfPage:
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
        case .png, .jpeg, .heic, .mov:
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

/// How a recording was made, kept next to it in history so it can be edited again later.
struct HistoryRecordingInfo: Codable, Equatable {
    var showsCursor: Bool
    var recordingAreaWidth: Double
    var recordingAreaHeight: Double
}

/// A recording in history, with whatever the editor needs that was saved alongside it.
struct HistoryRecordingSource {
    static let cursorFileName = "cursor.json"
    static let infoFileName = "recording.json"

    let videoURL: URL
    let mode: HistoryCaptureMode
    let cursorTelemetryURL: URL?
    let info: HistoryRecordingInfo?

    init(entry: HistoryEntry, videoURL: URL) {
        let dir = videoURL.deletingLastPathComponent()
        let cursorURL = dir.appendingPathComponent(Self.cursorFileName)
        self.videoURL = videoURL
        self.mode = entry.captureMode
        self.cursorTelemetryURL = FileManager.default.fileExists(atPath: cursorURL.path) ? cursorURL : nil
        self.info = (try? Data(contentsOf: dir.appendingPathComponent(Self.infoFileName)))
            .flatMap { try? JSONDecoder().decode(HistoryRecordingInfo.self, from: $0) }
    }
}

