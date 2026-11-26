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
    #expect(tracker.heldURL(for: entryID) == "https://share.example.com/fast.png")

    tracker.completePersistence(id: entryID)
    #expect(tracker.heldURL(for: entryID) == nil)
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

@Test("collections order PDF pages, interleave screenshots, and protect entries from retention cleanup")
func collectionsLifecycleAndRetentionProtection() throws {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let store = try HistoryStore(directory: tmpDir)
    let oldDate = Calendar.current.date(byAdding: .day, value: -60, to: Date())!

    let collection = HistoryCollection(title: "Lecture 01", createdAt: oldDate)
    try store.createCollection(collection)

    let page1 = HistoryEntry(
        createdAt: oldDate,
        captureMode: .pdfPage,
        imageWidth: 1920,
        imageHeight: 1080,
        sourceAppName: "Lecture 01",
        sourceWindowTitle: "Page 1",
        thumbnailFileName: "t.jpg",
        fullImageFileName: "capture.png",
        fileSize: 2048
    )
    let page2 = HistoryEntry(
        createdAt: oldDate,
        captureMode: .pdfPage,
        imageWidth: 1920,
        imageHeight: 1080,
        sourceAppName: "Lecture 01",
        sourceWindowTitle: "Page 2",
        thumbnailFileName: "t.jpg",
        fullImageFileName: "capture.png",
        fileSize: 2048
    )
    let screenshot = HistoryEntry(
        createdAt: oldDate,
        captureMode: .area,
        imageWidth: 800,
        imageHeight: 600,
        sourceAppName: "Safari",
        thumbnailFileName: "t.jpg",
        fullImageFileName: "capture.png",
        fileSize: 1024
    )
    let unlinkedOldScreenshot = HistoryEntry(
        createdAt: oldDate,
        captureMode: .area,
        imageWidth: 640,
        imageHeight: 480,
        sourceAppName: "Notes",
        thumbnailFileName: "t.jpg",
        fullImageFileName: "capture.png",
        fileSize: 512
    )

    try store.insertEntryAndAddToCollection(page1, collectionID: collection.id)
    try store.insertEntryAndAddToCollection(page2, collectionID: collection.id)
    try store.insert(screenshot)
    try store.insert(unlinkedOldScreenshot)

    // PDF pages stay out of the main flat timeline.
    let mainEntries = try store.fetchAll(filter: .all)
    #expect(mainEntries.map(\.id).contains(screenshot.id))
    #expect(!mainEntries.map(\.id).contains(page1.id))
    #expect(try store.count(filter: .collections) == 1)

    // Interleave the screenshot between Page 1 and Page 2.
    try store.addEntries([screenshot.id], toCollection: collection.id, insertAt: 1)
    let interleaved = try store.fetchCollectionEntries(collectionID: collection.id)
    #expect(interleaved.map(\.id) == [page1.id, screenshot.id, page2.id])

    // Reorder: move Page 2 to the front.
    try store.reorderCollection(collectionID: collection.id, orderedEntryIDs: [page2.id, page1.id, screenshot.id])
    let reordered = try store.fetchCollectionEntries(collectionID: collection.id)
    #expect(reordered.map(\.id) == [page2.id, page1.id, screenshot.id])

    let summaries = try store.fetchCollectionSummaries()
    #expect(summaries.count == 1)
    #expect(summaries[0].pageCount == 3)
    #expect(summaries[0].coverEntry?.id == page2.id)

    // Retention cleanup deletes unlinked old screenshots, but preserves collection-referenced entries.
    let removedCount = try HistoryCleanup.enforce(store: store, retention: .oneWeek)
    #expect(removedCount == 1)
    #expect(try store.fetchCollectionEntries(collectionID: collection.id).map(\.id) == [page2.id, page1.id, screenshot.id])
    #expect(try store.fetchAll(filter: .screenshots).map(\.id) == [screenshot.id])

    // Removing a regular screenshot from a collection keeps the screenshot in History.
    let orphanedFromScreenshotRemove = try store.removeEntries([screenshot.id], fromCollection: collection.id)
    #expect(orphanedFromScreenshotRemove.isEmpty)
    #expect(try store.fetchAll(filter: .screenshots).map(\.id) == [screenshot.id])

    // Removing a .pdfPage from a collection deletes the orphaned .pdfPage entry.
    let orphanedFromPageRemove = try store.removeEntries([page1.id], fromCollection: collection.id)
    #expect(orphanedFromPageRemove.map(\.id) == [page1.id])
    #expect(try store.fetchCollectionEntries(collectionID: collection.id).map(\.id) == [page2.id])

    // Deleting the collection deletes remaining orphaned .pdfPage entries and keeps screenshots.
    let orphanedFromDelete = try store.deleteCollection(id: collection.id)
    #expect(orphanedFromDelete.map(\.id) == [page2.id])
    #expect(try store.count(filter: .collections) == 0)
    #expect(try store.fetchAll(filter: .screenshots).map(\.id) == [screenshot.id])
}
