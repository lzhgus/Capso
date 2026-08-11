import AppKit
import CaptureKit
import SharedKit
import XCTest
@testable import Capso

@MainActor
final class ScreenshotClipboardContentTests: XCTestCase {
    func testFilePathContentCopiesReadableManagedFileWithoutPreview() throws {
        let settings = makeSettings()
        settings.screenshotClipboardContent = .filePath
        settings.screenshotOutputFormat = .png
        let coordinator = CaptureCoordinator(settings: settings)
        let pasteboard = makePasteboard()

        XCTAssertTrue(coordinator.copyScreenshotToClipboard(
            try makeCaptureResult(),
            entryID: UUID(),
            pasteboard: pasteboard
        ))

        let path = try XCTUnwrap(pasteboard.string(forType: .string))
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertTrue(path.hasPrefix("/"))
        XCTAssertEqual((path as NSString).pathExtension, "png")
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: path))
    }

    func testFilePathContentPrefersSuccessfulAutoSaveOutput() throws {
        let settings = makeSettings()
        settings.screenshotClipboardContent = .filePath
        let coordinator = CaptureCoordinator(settings: settings)
        let pasteboard = makePasteboard()
        let savedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-autosave-\(UUID().uuidString)")
            .appendingPathExtension("png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: savedURL)
        defer { try? FileManager.default.removeItem(at: savedURL) }

        XCTAssertTrue(coordinator.copyScreenshotToClipboard(
            try makeCaptureResult(),
            entryID: UUID(),
            preferredFileURL: savedURL,
            pasteboard: pasteboard
        ))

        XCTAssertEqual(pasteboard.string(forType: .string), savedURL.path)
    }

    func testDefaultPostCaptureCopiesFilePathWhenPreviewIsDisabled() throws {
        let settings = makeSettings()
        settings.screenshotShowPreview = false
        settings.screenshotAutoCopy = true
        settings.screenshotAutoSave = false
        settings.screenshotClipboardContent = .filePath
        let coordinator = CaptureCoordinator(settings: settings)
        let pasteboard = makePasteboard()

        coordinator.applyDefaultPostCaptureActions(
            try makeCaptureResult(),
            entryID: UUID(),
            pasteboard: pasteboard
        )

        let path = try XCTUnwrap(pasteboard.string(forType: .string))
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: path))
    }

    func testDefaultPostCaptureCopiesAutoSaveOutputPathWithoutDuplicateTemporaryFile() throws {
        let settings = makeSettings()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotClipboardAutoSaveTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        settings.setExportLocation(exportDirectory)
        settings.screenshotShowPreview = false
        settings.screenshotAutoCopy = true
        settings.screenshotAutoSave = true
        settings.screenshotClipboardContent = .filePath
        let coordinator = CaptureCoordinator(settings: settings)
        let pasteboard = makePasteboard()

        coordinator.applyDefaultPostCaptureActions(
            try makeCaptureResult(),
            entryID: UUID(),
            pasteboard: pasteboard
        )

        let copiedPath = try XCTUnwrap(pasteboard.string(forType: .string))
        defer {
            if !copiedPath.hasPrefix(exportDirectory.path) {
                try? FileManager.default.removeItem(atPath: copiedPath)
            }
        }
        let savedFiles = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(savedFiles.count, 1)
        XCTAssertEqual(
            URL(fileURLWithPath: copiedPath).resolvingSymlinksInPath(),
            savedFiles[0].resolvingSymlinksInPath()
        )
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: copiedPath))
    }

    func testQuickAccessCopyReusesAutoSaveOutputPath() throws {
        let settings = makeSettings()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotClipboardQuickAccessTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        settings.setExportLocation(exportDirectory)
        settings.screenshotAutoCopy = false
        settings.screenshotAutoSave = true
        settings.screenshotClipboardContent = .filePath
        let coordinator = CaptureCoordinator(settings: settings)
        let pasteboard = makePasteboard()
        let result = try makeCaptureResult()
        let entryID = UUID()

        let savedFileURL = try XCTUnwrap(coordinator.applyDefaultPostCaptureActions(
            result,
            entryID: entryID,
            pasteboard: pasteboard
        ))
        let window = coordinator.showQuickAccess(
            for: result,
            entryID: entryID,
            autoUpload: false,
            preferredFileURL: savedFileURL,
            pasteboard: pasteboard
        )
        window.onCopy?()

        XCTAssertEqual(
            URL(fileURLWithPath: try XCTUnwrap(pasteboard.string(forType: .string)))
                .resolvingSymlinksInPath(),
            savedFileURL.resolvingSymlinksInPath()
        )
    }

    func testQuickAccessSaveReplacesManagedTemporaryPathWithSavedPath() throws {
        let settings = makeSettings()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotClipboardQuickAccessSaveTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        settings.setExportLocation(exportDirectory)
        settings.screenshotAutoCopy = true
        settings.screenshotAutoSave = false
        settings.screenshotClipboardContent = .filePath
        let coordinator = CaptureCoordinator(settings: settings)
        let pasteboard = makePasteboard()
        let result = try makeCaptureResult()
        let entryID = UUID()

        coordinator.applyDefaultPostCaptureActions(
            result,
            entryID: entryID,
            pasteboard: pasteboard
        )
        let temporaryPath = try XCTUnwrap(pasteboard.string(forType: .string))
        defer { try? FileManager.default.removeItem(atPath: temporaryPath) }

        let window = coordinator.showQuickAccess(
            for: result,
            entryID: entryID,
            autoUpload: false,
            pasteboard: pasteboard
        )
        window.onSave?()

        let savedPath = try XCTUnwrap(pasteboard.string(forType: .string))
        let savedFiles = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertNotEqual(
            URL(fileURLWithPath: savedPath).resolvingSymlinksInPath(),
            URL(fileURLWithPath: temporaryPath).resolvingSymlinksInPath()
        )
        XCTAssertEqual(savedFiles.count, 1)
        XCTAssertEqual(
            URL(fileURLWithPath: savedPath).resolvingSymlinksInPath(),
            savedFiles[0].resolvingSymlinksInPath()
        )
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: savedPath))
    }

    func testHistoryScreenshotCopyUsesExistingReadableFilePath() throws {
        let settings = makeSettings()
        settings.screenshotClipboardContent = .filePath
        let coordinator = HistoryCoordinator(settings: settings)
        let pasteboard = makePasteboard()
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-history-\(UUID().uuidString)")
            .appendingPathExtension("png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        XCTAssertTrue(coordinator.copyScreenshotToClipboard(
            try makeCaptureResult().image,
            preferredFileURL: sourceURL,
            pasteboard: pasteboard
        ))

        XCTAssertEqual(pasteboard.string(forType: .string), sourceURL.path)
    }

    private func makeSettings() -> AppSettings {
        let suite = "ScreenshotClipboardContentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppSettings(defaults: defaults)
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("ScreenshotClipboardContentTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        return pasteboard
    }

    private func makeCaptureResult() throws -> CaptureResult {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 8,
            height: 6,
            bitsPerComponent: 8,
            bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        return CaptureResult(
            image: try XCTUnwrap(context.makeImage()),
            mode: .area,
            captureRect: CGRect(x: 0, y: 0, width: 8, height: 6),
            windowName: "Terminal",
            appName: "Agent",
            timestamp: Date(timeIntervalSince1970: 1_800),
            displayID: 1
        )
    }
}
