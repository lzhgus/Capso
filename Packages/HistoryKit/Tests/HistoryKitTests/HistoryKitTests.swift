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
    try store.setCloudURL(id: entryID, url: "https://share.example.com/abc.png")
    let afterSet = try store.fetchAll(filter: .all).first { $0.id == entryID }
    #expect(afterSet?.cloudURL == "https://share.example.com/abc.png")

    // Clear cloudURL
    try store.setCloudURL(id: entryID, url: nil)
    let afterClear = try store.fetchAll(filter: .all).first { $0.id == entryID }
    #expect(afterClear?.cloudURL == nil)

    // Setting on a non-existent ID is silently a no-op (must not throw)
    try store.setCloudURL(id: UUID(), url: "https://x.com/none.png")
}
