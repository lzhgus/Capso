// Packages/HistoryKit/Sources/HistoryKit/HistoryEntry.swift
import Foundation
import GRDB

/// The type of capture stored in history.
public enum HistoryCaptureMode: String, Codable, Sendable, DatabaseValueConvertible {
    case area
    case fullscreen
    case window
    case recording
    case gif
    case pdfPage
}

/// A single entry in the screenshot/recording history.
public struct HistoryEntry: Identifiable, Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "history_entries"

    public let id: UUID
    public let createdAt: Date
    public let captureMode: HistoryCaptureMode
    public let imageWidth: Int
    public let imageHeight: Int
    public let sourceAppName: String?
    public let sourceAppBundleID: String?
    public let sourceWindowTitle: String?
    public let thumbnailFileName: String
    public let fullImageFileName: String
    public var annotationFileName: String?
    public let fileSize: Int64
    public var cloudURL: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        captureMode: HistoryCaptureMode,
        imageWidth: Int,
        imageHeight: Int,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        sourceWindowTitle: String? = nil,
        thumbnailFileName: String,
        fullImageFileName: String,
        annotationFileName: String? = nil,
        fileSize: Int64,
        cloudURL: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.captureMode = captureMode
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceWindowTitle = sourceWindowTitle
        self.thumbnailFileName = thumbnailFileName
        self.fullImageFileName = fullImageFileName
        self.annotationFileName = annotationFileName
        self.fileSize = fileSize
        self.cloudURL = cloudURL
    }
}

/// An ordered deck/collection of pages (e.g., an imported PDF combined with interleaved screenshots).
public struct HistoryCollection: Identifiable, Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "history_collections"

    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// Ordered membership row linking a `HistoryEntry` into a `HistoryCollection`.
public struct HistoryCollectionItem: Identifiable, Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "history_collection_items"

    public let id: UUID
    public let collectionID: UUID
    public let entryID: UUID
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        collectionID: UUID,
        entryID: UUID,
        sortOrder: Int
    ) {
        self.id = id
        self.collectionID = collectionID
        self.entryID = entryID
        self.sortOrder = sortOrder
    }
}

/// Summary view model for displaying a collection card in the history browser.
public struct HistoryCollectionSummary: Identifiable, Sendable, Equatable {
    public let collection: HistoryCollection
    public let pageCount: Int
    public let coverEntry: HistoryEntry?

    public var id: UUID { collection.id }

    public init(collection: HistoryCollection, pageCount: Int, coverEntry: HistoryEntry?) {
        self.collection = collection
        self.pageCount = pageCount
        self.coverEntry = coverEntry
    }
}
