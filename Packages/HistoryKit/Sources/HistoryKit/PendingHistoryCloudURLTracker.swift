import Foundation

/// Bridges cloud uploads that finish before their asynchronous history insert.
public struct PendingHistoryCloudURLTracker: Sendable {
    private var pendingEntryIDs: Set<UUID> = []
    private var heldURLs: [UUID: String] = [:]

    public init() {}

    public mutating func begin(id: UUID) {
        pendingEntryIDs.insert(id)
    }

    public func contains(_ id: UUID) -> Bool {
        pendingEntryIDs.contains(id)
    }

    public var heldURLsForPersistence: [UUID: String] {
        heldURLs
    }

    public func heldURL(for id: UUID) -> String? {
        heldURLs[id]
    }

    @discardableResult
    public mutating func hold(url: String, for id: UUID) -> Bool {
        guard pendingEntryIDs.contains(id) else { return false }
        heldURLs[id] = url
        return true
    }

    public mutating func finish(id: UUID) -> String? {
        pendingEntryIDs.remove(id)
        return heldURLs[id]
    }

    public mutating func completePersistence(id: UUID) {
        heldURLs.removeValue(forKey: id)
    }

    public mutating func cancel(id: UUID) {
        pendingEntryIDs.remove(id)
        heldURLs.removeValue(forKey: id)
    }
}
