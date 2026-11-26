// Packages/HistoryKit/Sources/HistoryKit/HistoryCleanup.swift
import Foundation

/// Retention policy for history entries.
public enum HistoryRetention: String, CaseIterable, Sendable {
    case oneWeek
    case twoWeeks
    case oneMonth
    case unlimited

    public var label: String {
        switch self {
        case .oneWeek: "1 Week"
        case .twoWeeks: "2 Weeks"
        case .oneMonth: "1 Month"
        case .unlimited: "Unlimited"
        }
    }

    /// Number of days to keep entries, or nil for unlimited.
    public var days: Int? {
        switch self {
        case .oneWeek: 7
        case .twoWeeks: 14
        case .oneMonth: 30
        case .unlimited: nil
        }
    }
}

/// Enforces retention policy by deleting expired entries and their files.
public enum HistoryCleanup {
    /// Delete entries older than the retention period.
    /// Returns the number of entries removed.
    @discardableResult
    public static func enforce(store: HistoryStore, retention: HistoryRetention) throws -> Int {
        guard let days = retention.days else { return 0 }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let expired = try store.deleteOlderThan(cutoff)

        let fm = FileManager.default
        for entry in expired {
            let entryDir = store.entriesDirectory.appendingPathComponent(entry.id.uuidString, isDirectory: true)
            try? fm.removeItem(at: entryDir)
        }

        return expired.count
    }

    /// Delete all history entries, collections, and their files.
    public static func clearAll(store: HistoryStore) throws {
        try store.deleteAllCollections()
        let all = try store.fetchAllIncludingCollectionPages()
        let fm = FileManager.default
        for entry in all {
            try store.delete(id: entry.id)
            let entryDir = store.entriesDirectory.appendingPathComponent(entry.id.uuidString, isDirectory: true)
            try? fm.removeItem(at: entryDir)
        }
    }
}
