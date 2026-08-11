// Packages/SharedKit/Tests/SharedKitTests/QuickAccessDragFileStoreTests.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import SharedKit

@Suite("QuickAccessDragFileStore")
struct QuickAccessDragFileStoreTests {
    @Test("creates readable PNG file in app-managed temp storage")
    func createsReadablePNGFile() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let store = QuickAccessDragFileStore(directory: directory)
        let image = try makeImage()

        let url = try store.fileURL(for: image, id: UUID())

        #expect(url.deletingLastPathComponent() == directory)
        #expect(url.pathExtension == "png")
        #expect(FileManager.default.isReadableFile(atPath: url.path))
        let data = try Data(contentsOf: url)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("uses screenshot output options and filename template")
    func usesOutputOptionsAndFilenameTemplate() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let store = QuickAccessDragFileStore(directory: directory)
        let image = try makeImage()

        let url = try store.fileURL(
            for: image,
            id: UUID(),
            output: ScreenshotOutputOptions(format: .jpeg, quality: 0.85),
            date: Date(timeIntervalSince1970: 1_800),
            sourceAppName: "Safari",
            sourceWindowTitle: "Example",
            template: "Drag {app} {window}"
        )

        #expect(url.deletingLastPathComponent() == directory)
        #expect(url.lastPathComponent == "Drag Safari Example.jpeg")
        let data = try Data(contentsOf: url)
        #expect(data.starts(with: [0xFF, 0xD8]))
    }

    @Test("writes HEIC bytes when the output format is HEIC")
    func writesHEICOutput() throws {
        guard ScreenshotOutputFormat.heic.isAvailable else { return }
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let store = QuickAccessDragFileStore(directory: directory)
        let image = try makeImage()

        let url = try store.fileURL(
            for: image,
            id: UUID(),
            output: ScreenshotOutputOptions(format: .heic, quality: 0.85),
            date: Date(timeIntervalSince1970: 1_800),
            template: "Drag"
        )

        #expect(url.lastPathComponent == "Drag.heic")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.heic.identifier)
    }

    @Test("returns the same readable file for repeated access")
    func returnsSameFileForRepeatedAccess() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let store = QuickAccessDragFileStore(directory: directory)
        let image = try makeImage()
        let id = UUID()

        let firstURL = try store.fileURL(for: image, id: id)
        let secondURL = try store.fileURL(for: image, id: id)

        #expect(firstURL == secondURL)
        #expect(FileManager.default.isReadableFile(atPath: secondURL.path))
    }

    @Test("creates unique files for distinct captures")
    func createsUniqueFilesForDistinctCaptures() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let store = QuickAccessDragFileStore(directory: directory)
        let image = try makeImage()

        let firstURL = try store.fileURL(for: image, id: UUID())
        let secondURL = try store.fileURL(for: image, id: UUID())

        #expect(firstURL != secondURL)
        #expect(FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path))
    }

    @Test("adds a suffix when generated drag filenames collide")
    func addsSuffixWhenGeneratedNamesCollide() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let store = QuickAccessDragFileStore(directory: directory)
        let image = try makeImage()

        let firstURL = try store.fileURL(
            for: image,
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_800),
            template: "Same Name"
        )
        let secondURL = try store.fileURL(
            for: image,
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_800),
            template: "Same Name"
        )

        #expect(firstURL.lastPathComponent == "Same Name.png")
        #expect(secondURL.lastPathComponent == "Same Name 2.png")
    }

    @Test("prunes every stale output format while preserving active drag files")
    func prunesStaleFiles() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let now = Date(timeIntervalSince1970: 2_000)
        let store = QuickAccessDragFileStore(directory: directory, staleFileAge: 60)
        let activeURL = try store.fileURL(for: try makeImage(), id: UUID())
        let staleURLs = ["stale.png", "stale.jpeg", "stale.jpg", "stale.heic"]
            .map { directory.appendingPathComponent($0) }
        let recentURL = directory.appendingPathComponent("recent.png")
        for url in staleURLs {
            try Data([1]).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-120)], ofItemAtPath: url.path)
        }
        try Data([2]).write(to: recentURL)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)], ofItemAtPath: recentURL.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-120)], ofItemAtPath: activeURL.path)

        let removed = try store.pruneStaleFiles(referenceDate: now)

        #expect(removed.map(\.lastPathComponent).sorted() == staleURLs.map(\.lastPathComponent).sorted())
        for url in staleURLs {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
        #expect(FileManager.default.fileExists(atPath: recentURL.path))
        #expect(FileManager.default.fileExists(atPath: activeURL.path))
    }

    @Test("reports encoding failure without creating a file")
    func reportsEncodingFailure() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let store = QuickAccessDragFileStore(directory: directory, encoder: { _ in nil })

        #expect(throws: QuickAccessDragFileStoreError.encodingFailed) {
            _ = try store.fileURL(for: try makeImage(), id: UUID())
        }
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents.isEmpty)
    }

    @Test("reports storage failure when the temp directory cannot be prepared")
    func reportsStorageFailure() throws {
        let parent = temporaryDirectory()
        defer { remove(parent) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let fileInsteadOfDirectory = parent.appendingPathComponent("drag-files")
        try Data([1]).write(to: fileInsteadOfDirectory)
        let store = QuickAccessDragFileStore(directory: fileInsteadOfDirectory)

        #expect(throws: QuickAccessDragFileStoreError.storageUnavailable) {
            _ = try store.fileURL(for: try makeImage(), id: UUID())
        }
    }

    @Test("removes the cached file for a dismissed drag preview")
    func removesCachedFileForDismissedPreview() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let store = QuickAccessDragFileStore(directory: directory)
        let id = UUID()
        let url = try store.fileURL(for: try makeImage(), id: id)

        try store.removeFile(for: id)

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickAccessDragFileStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeImage() throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestError.imageCreationFailed
        }

        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))

        guard let image = context.makeImage() else {
            throw TestError.imageCreationFailed
        }
        return image
    }

    private enum TestError: Error {
        case imageCreationFailed
    }
}
