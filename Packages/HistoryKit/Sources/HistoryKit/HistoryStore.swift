// Packages/HistoryKit/Sources/HistoryKit/HistoryStore.swift
import Foundation
import GRDB

/// Filter for querying history entries.
public enum HistoryFilter: Sendable {
    case all
    case screenshots  // area, fullscreen, window
    case recordings   // recording, gif
}

/// Persistent store for capture history backed by SQLite via GRDB.
public final class HistoryStore: Sendable {
    private let dbQueue: DatabaseQueue

    /// The root directory for all history data (database + entry folders).
    public let storageDirectory: URL

    /// Directory where per-entry image folders live.
    public var entriesDirectory: URL {
        storageDirectory.appendingPathComponent("entries", isDirectory: true)
    }

    public init(directory: URL? = nil) throws {
        let base = directory ?? Self.defaultDirectory()
        self.storageDirectory = base

        let fm = FileManager.default
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: base.appendingPathComponent("entries", isDirectory: true),
            withIntermediateDirectories: true
        )

        let dbPath = base.appendingPathComponent("history.sqlite").path
        dbQueue = try DatabaseQueue(path: dbPath)
        try migrate()
    }

    private static func defaultDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("com.awesomemacapps.capso", isDirectory: true)
            .appendingPathComponent("history", isDirectory: true)
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_history") { db in
            try db.create(table: HistoryEntry.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("captureMode", .text).notNull()
                t.column("imageWidth", .integer).notNull()
                t.column("imageHeight", .integer).notNull()
                t.column("sourceAppName", .text)
                t.column("sourceAppBundleID", .text)
                t.column("sourceWindowTitle", .text)
                t.column("thumbnailFileName", .text).notNull()
                t.column("fullImageFileName", .text).notNull()
                t.column("annotationFileName", .text)
                t.column("fileSize", .integer).notNull()
            }
        }
        migrator.registerMigration("v2_add_cloud_url") { db in
            try db.alter(table: HistoryEntry.databaseTableName) { t in
                t.add(column: "cloudURL", .text)
            }
        }
        try migrator.migrate(dbQueue)
    }

    // MARK: - CRUD

    public func insert(_ entry: HistoryEntry) throws {
        try dbQueue.write { db in
            try entry.insert(db)
        }
    }

    public func fetchAll(filter: HistoryFilter = .all) throws -> [HistoryEntry] {
        try dbQueue.read { db in
            switch filter {
            case .all:
                return try HistoryEntry
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            case .screenshots:
                let modes: [HistoryCaptureMode] = [.area, .fullscreen, .window]
                return try HistoryEntry
                    .filter(modes.map(\.rawValue).contains(Column("captureMode")))
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            case .recordings:
                let modes: [HistoryCaptureMode] = [.recording, .gif]
                return try HistoryEntry
                    .filter(modes.map(\.rawValue).contains(Column("captureMode")))
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            }
        }
    }

    public func delete(id: UUID) throws {
        try dbQueue.write { db in
            _ = try HistoryEntry.deleteOne(db, id: id)
        }
    }

    /// Set or clear the cloud share URL for a capture.
    /// Silently no-ops if no row matches `id` — by design: if the user deletes a
    /// capture while an upload is in flight, the URL has nowhere to land but the
    /// upload itself already succeeded; this is not an error condition.
    public func setCloudURL(id: UUID, url: String?) throws {
        try dbQueue.write { db in
            _ = try HistoryEntry
                .filter(id: id)
                .updateAll(db, Column("cloudURL").set(to: url))
        }
    }

    public func deleteOlderThan(_ date: Date) throws -> [HistoryEntry] {
        try dbQueue.write { db in
            let old = try HistoryEntry
                .filter(Column("createdAt") < date)
                .fetchAll(db)
            _ = try HistoryEntry
                .filter(Column("createdAt") < date)
                .deleteAll(db)
            return old
        }
    }

    public func count(filter: HistoryFilter = .all) throws -> Int {
        try dbQueue.read { db in
            switch filter {
            case .all:
                return try HistoryEntry.fetchCount(db)
            case .screenshots:
                let modes: [HistoryCaptureMode] = [.area, .fullscreen, .window]
                return try HistoryEntry
                    .filter(modes.map(\.rawValue).contains(Column("captureMode")))
                    .fetchCount(db)
            case .recordings:
                let modes: [HistoryCaptureMode] = [.recording, .gif]
                return try HistoryEntry
                    .filter(modes.map(\.rawValue).contains(Column("captureMode")))
                    .fetchCount(db)
            }
        }
    }

    public func totalFileSize() throws -> Int64 {
        try dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT COALESCE(SUM(fileSize), 0) FROM \(HistoryEntry.databaseTableName)")
            return row?[0] as? Int64 ?? 0
        }
    }

    public func update(_ entry: HistoryEntry) throws {
        try dbQueue.write { db in
            try entry.update(db)
        }
    }
}
