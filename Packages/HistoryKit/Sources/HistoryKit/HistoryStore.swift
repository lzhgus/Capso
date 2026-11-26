// Packages/HistoryKit/Sources/HistoryKit/HistoryStore.swift
import Foundation
import GRDB

/// Filter for querying history entries.
public enum HistoryFilter: Sendable, Equatable {
    case all
    case screenshots  // area, fullscreen, window
    case recordings   // recording, gif
    case collections  // PDF decks / collections
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
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
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
        migrator.registerMigration("v3_add_history_collections") { db in
            try db.create(table: HistoryCollection.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("updatedAt", .datetime).notNull().indexed()
            }
            try db.create(table: HistoryCollectionItem.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("collectionID", .text).notNull()
                    .references(HistoryCollection.databaseTableName, onDelete: .cascade)
                    .indexed()
                t.column("entryID", .text).notNull()
                    .references(HistoryEntry.databaseTableName, onDelete: .cascade)
                    .indexed()
                t.column("sortOrder", .integer).notNull()
            }
        }
        try migrator.migrate(dbQueue)
    }

    // MARK: - Entry CRUD

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
                    .filter(Column("captureMode") != HistoryCaptureMode.pdfPage.rawValue)
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
            case .collections:
                return []
            }
        }
    }

    /// Returns every entry row in the database, including `.pdfPage` rows. Used by cleanup.
    public func fetchAllIncludingCollectionPages() throws -> [HistoryEntry] {
        try dbQueue.read { db in
            try HistoryEntry
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    public func delete(id: UUID) throws {
        try dbQueue.write { db in
            _ = try HistoryEntry.deleteOne(db, id: id)
        }
    }

    /// Set or clear the cloud share URL for a capture.
    /// Returns whether a row matched `id`. Callers can use a `false` result to
    /// defer an update while an asynchronous history insert is still pending.
    @discardableResult
    public func setCloudURL(id: UUID, url: String?) throws -> Bool {
        try dbQueue.write { db in
            try HistoryEntry
                .filter(id: id)
                .updateAll(db, Column("cloudURL").set(to: url)) > 0
        }
    }

    /// Deletes entries older than `date`, excluding any entry currently referenced
    /// by a collection so imported PDFs and interleaved screenshots are protected
    /// from automatic retention cleanup.
    public func deleteOlderThan(_ date: Date) throws -> [HistoryEntry] {
        try dbQueue.write { db in
            let protectedIDs = try UUID.fetchSet(
                db,
                sql: "SELECT DISTINCT entryID FROM \(HistoryCollectionItem.databaseTableName)"
            )
            let candidates = try HistoryEntry
                .filter(Column("createdAt") < date)
                .fetchAll(db)
            let expired = candidates.filter { !protectedIDs.contains($0.id) }
            for entry in expired {
                _ = try HistoryEntry.deleteOne(db, id: entry.id)
            }
            return expired
        }
    }

    public func count(filter: HistoryFilter = .all) throws -> Int {
        try dbQueue.read { db in
            switch filter {
            case .all:
                let nonPDFCount = try HistoryEntry
                    .filter(Column("captureMode") != HistoryCaptureMode.pdfPage.rawValue)
                    .fetchCount(db)
                let collectionCount = try HistoryCollection.fetchCount(db)
                return nonPDFCount + collectionCount
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
            case .collections:
                return try HistoryCollection.fetchCount(db)
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

    // MARK: - Collection CRUD

    public func createCollection(_ collection: HistoryCollection) throws {
        try dbQueue.write { db in
            try collection.insert(db)
        }
    }

    public func fetchCollectionSummaries() throws -> [HistoryCollectionSummary] {
        try dbQueue.read { db in
            let collections = try HistoryCollection
                .order(Column("updatedAt").desc, Column("createdAt").desc)
                .fetchAll(db)
            return try collections.map { collection in
                let items = try HistoryCollectionItem
                    .filter(Column("collectionID") == collection.id)
                    .order(Column("sortOrder").asc)
                    .fetchAll(db)
                let coverEntry: HistoryEntry?
                if let firstEntryID = items.first?.entryID {
                    coverEntry = try HistoryEntry.fetchOne(db, id: firstEntryID)
                } else {
                    coverEntry = nil
                }
                return HistoryCollectionSummary(
                    collection: collection,
                    pageCount: items.count,
                    coverEntry: coverEntry
                )
            }
        }
    }

    public func fetchCollectionEntries(collectionID: UUID) throws -> [HistoryEntry] {
        try dbQueue.read { db in
            let sql = """
                SELECT e.*
                FROM \(HistoryEntry.databaseTableName) e
                INNER JOIN \(HistoryCollectionItem.databaseTableName) ci
                    ON ci.entryID = e.id
                WHERE ci.collectionID = ?
                ORDER BY ci.sortOrder ASC
                """
            return try HistoryEntry.fetchAll(db, sql: sql, arguments: [collectionID])
        }
    }

    public func renameCollection(id: UUID, title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try dbQueue.write { db in
            _ = try HistoryCollection
                .filter(id: id)
                .updateAll(
                    db,
                    Column("title").set(to: trimmed),
                    Column("updatedAt").set(to: Date())
                )
        }
    }

    /// Inserts `entry` and adds it to `collectionID` in a single atomic transaction.
    public func insertEntryAndAddToCollection(
        _ entry: HistoryEntry,
        collectionID: UUID,
        insertAt index: Int? = nil
    ) throws {
        try dbQueue.write { db in
            try entry.insert(db)
            try Self.addEntryIDs([entry.id], toCollection: collectionID, insertAt: index, in: db)
        }
    }

    /// Appends or inserts existing history entry IDs into `collectionID`, skipping duplicates already in the collection.
    public func addEntries(
        _ entryIDs: [UUID],
        toCollection collectionID: UUID,
        insertAt index: Int? = nil
    ) throws {
        guard !entryIDs.isEmpty else { return }
        try dbQueue.write { db in
            try Self.addEntryIDs(entryIDs, toCollection: collectionID, insertAt: index, in: db)
        }
    }

    /// Reorders all items in `collectionID` to match `orderedEntryIDs`.
    public func reorderCollection(collectionID: UUID, orderedEntryIDs: [UUID]) throws {
        try dbQueue.write { db in
            let existing = try HistoryCollectionItem
                .filter(Column("collectionID") == collectionID)
                .order(Column("sortOrder").asc)
                .fetchAll(db)
            let existingByEntryID = Dictionary(uniqueKeysWithValues: existing.map { ($0.entryID, $0) })

            var finalOrder: [HistoryCollectionItem] = []
            var seen = Set<UUID>()
            for entryID in orderedEntryIDs {
                if let item = existingByEntryID[entryID], seen.insert(entryID).inserted {
                    finalOrder.append(item)
                }
            }
            for item in existing where seen.insert(item.entryID).inserted {
                finalOrder.append(item)
            }

            for (idx, var item) in finalOrder.enumerated() {
                if item.sortOrder != idx {
                    item.sortOrder = idx
                    try item.update(db)
                }
            }
            _ = try HistoryCollection
                .filter(id: collectionID)
                .updateAll(db, Column("updatedAt").set(to: Date()))
        }
    }

    /// Removes `entryIDs` from `collectionID`. Returns any `.pdfPage` entries that are no longer
    /// referenced by any collection and have been removed from `history_entries` so the caller
    /// can remove their files on disk.
    @discardableResult
    public func removeEntries(
        _ entryIDs: [UUID],
        fromCollection collectionID: UUID
    ) throws -> [HistoryEntry] {
        guard !entryIDs.isEmpty else { return [] }
        return try dbQueue.write { db in
            _ = try HistoryCollectionItem
                .filter(Column("collectionID") == collectionID)
                .filter(entryIDs.contains(Column("entryID")))
                .deleteAll(db)

            try Self.renumberCollectionItems(collectionID: collectionID, in: db)
            _ = try HistoryCollection
                .filter(id: collectionID)
                .updateAll(db, Column("updatedAt").set(to: Date()))

            return try Self.deleteOrphanedPDFPages(candidateEntryIDs: entryIDs, in: db)
        }
    }

    /// Deletes a collection and returns any `.pdfPage` entries that are no longer referenced
    /// by any other collection so the caller can remove their files on disk.
    /// Regular screenshots linked into the collection remain untouched in History.
    @discardableResult
    public func deleteCollection(id: UUID) throws -> [HistoryEntry] {
        try dbQueue.write { db in
            let linkedEntryIDs = try UUID.fetchAll(
                db,
                sql: "SELECT entryID FROM \(HistoryCollectionItem.databaseTableName) WHERE collectionID = ?",
                arguments: [id]
            )
            _ = try HistoryCollection.deleteOne(db, id: id)
            return try Self.deleteOrphanedPDFPages(candidateEntryIDs: linkedEntryIDs, in: db)
        }
    }

    public func deleteAllCollections() throws {
        try dbQueue.write { db in
            _ = try HistoryCollection.deleteAll(db)
        }
    }

    private static func addEntryIDs(
        _ entryIDs: [UUID],
        toCollection collectionID: UUID,
        insertAt index: Int?,
        in db: Database
    ) throws {
        var items = try HistoryCollectionItem
            .filter(Column("collectionID") == collectionID)
            .order(Column("sortOrder").asc)
            .fetchAll(db)

        var existingIDs = Set(items.map(\.entryID))
        var toInsert: [HistoryCollectionItem] = []
        for entryID in entryIDs where existingIDs.insert(entryID).inserted {
            toInsert.append(HistoryCollectionItem(
                collectionID: collectionID,
                entryID: entryID,
                sortOrder: 0
            ))
        }
        guard !toInsert.isEmpty else { return }

        let targetIndex = max(0, min(index ?? items.count, items.count))
        items.insert(contentsOf: toInsert, at: targetIndex)

        for (idx, var item) in items.enumerated() {
            item.sortOrder = idx
            try item.save(db)
        }
        _ = try HistoryCollection
            .filter(id: collectionID)
            .updateAll(db, Column("updatedAt").set(to: Date()))
    }

    private static func renumberCollectionItems(collectionID: UUID, in db: Database) throws {
        let remaining = try HistoryCollectionItem
            .filter(Column("collectionID") == collectionID)
            .order(Column("sortOrder").asc)
            .fetchAll(db)
        for (idx, var item) in remaining.enumerated() where item.sortOrder != idx {
            item.sortOrder = idx
            try item.update(db)
        }
    }

    private static func deleteOrphanedPDFPages(
        candidateEntryIDs: [UUID],
        in db: Database
    ) throws -> [HistoryEntry] {
        guard !candidateEntryIDs.isEmpty else { return [] }
        var deleted: [HistoryEntry] = []
        for entryID in Set(candidateEntryIDs) {
            guard let entry = try HistoryEntry.fetchOne(db, id: entryID),
                  entry.captureMode == .pdfPage else { continue }
            let remainingRefs = try HistoryCollectionItem
                .filter(Column("entryID") == entryID)
                .fetchCount(db)
            if remainingRefs == 0 {
                _ = try HistoryEntry.deleteOne(db, id: entryID)
                deleted.append(entry)
            }
        }
        return deleted
    }
}
