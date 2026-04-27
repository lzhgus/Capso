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
}

/// A single entry in the screenshot/recording history.
public struct HistoryEntry: Identifiable, Codable, Sendable, FetchableRecord, PersistableRecord {
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
