// Packages/HistoryKit/Tests/HistoryKitTests/HistoryKitTests.swift
import Testing
@testable import HistoryKit
import Foundation

@Test func placeholder() async throws {
    // Placeholder test
}

@Test("setCloudURL round-trips through GRDB")
func setCloudURLRoundTrip() throws {
    // Set up an isolated on-disk store in a temporary directory so we exercise
    // the real SQLite path (including migrations) without polluting app data.
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let store = try HistoryStore(directory: tmpDir)

    // Insert a fresh entry
    let entryID = UUID()
    let entry = HistoryEntry(
        id: entryID,
        createdAt: Date(),
        captureMode: .area,
        imageWidth: 100,
        imageHeight: 100,
        thumbnailFileName: "t.jpg",
        fullImageFileName: "f.png",
        fileSize: 1024
    )
    try store.insert(entry)

    // Initially, cloudURL is nil
    let initial = try store.fetchAll(filter: .all).first { $0.id == entryID }
    #expect(initial?.cloudURL == nil)

    // Set cloudURL
    let setMatchedEntry = try store.setCloudURL(id: entryID, url: "https://share.example.com/abc.png")
    #expect(setMatchedEntry == true)
    let afterSet = try store.fetchAll(filter: .all).first { $0.id == entryID }
    #expect(afterSet?.cloudURL == "https://share.example.com/abc.png")

    // Clear cloudURL
    let clearMatchedEntry = try store.setCloudURL(id: entryID, url: nil)
    #expect(clearMatchedEntry == true)
    let afterClear = try store.fetchAll(filter: .all).first { $0.id == entryID }
    #expect(afterClear?.cloudURL == nil)

    // Setting on a non-existent ID is silently a no-op (must not throw)
    let missingEntryMatched = try store.setCloudURL(id: UUID(), url: "https://x.com/none.png")
    #expect(missingEntryMatched == false)
}

@Test("holds a fast upload URL until the history insert finishes")
func pendingHistoryURLFinishesWithInsert() {
    let entryID = UUID()
    var tracker = PendingHistoryCloudURLTracker()

    tracker.begin(id: entryID)
    let heldURL = tracker.hold(url: "https://share.example.com/fast.png", for: entryID)
    #expect(heldURL)
    #expect(tracker.finish(id: entryID) == "https://share.example.com/fast.png")
    #expect(!tracker.contains(entryID))
}

@Test("cancelling a failed history insert clears pending state and URL")
func pendingHistoryURLCancelsWithFailedInsert() {
    let entryID = UUID()
    var tracker = PendingHistoryCloudURLTracker()

    tracker.begin(id: entryID)
    let heldURL = tracker.hold(url: "https://share.example.com/orphan.png", for: entryID)
    #expect(heldURL)
    tracker.cancel(id: entryID)

    #expect(!tracker.contains(entryID))
    #expect(tracker.finish(id: entryID) == nil)
}
