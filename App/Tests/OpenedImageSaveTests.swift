import AppKit
import XCTest
import SharedKit
@testable import Capso

@MainActor
final class OpenedImageSaveTests: XCTestCase {
    func testHandleOpenedFileSaveWithCopyBehaviorSavesNewFileAndLeavesOriginalUntouched() throws {
        let (coordinator, settings, exportDir) = try makeCoordinatorWithTempExport()
        defer { try? FileManager.default.removeItem(at: exportDir) }
        settings.openedImageSaveBehavior = .copy

        let originalURL = try writePNG(width: 5, height: 5, in: exportDir)
        let originalData = try Data(contentsOf: originalURL)
        let rendered = try makeTestImage(width: 9, height: 3)

        let before = try FileManager.default.contentsOfDirectory(at: exportDir, includingPropertiesForKeys: nil)
        let didProceed = coordinator.handleOpenedFileSave(
            rendered, originalURL: originalURL, sourceAppName: nil, sourceWindowTitle: nil, date: Date()
        )
        let after = try FileManager.default.contentsOfDirectory(at: exportDir, includingPropertiesForKeys: nil)

        XCTAssertTrue(didProceed)
        XCTAssertEqual(after.count, before.count + 1)
        XCTAssertEqual(try Data(contentsOf: originalURL), originalData)
    }

    func testHandleOpenedFileSaveWithOverwriteBehaviorRewritesOriginalFileInPlace() throws {
        let (coordinator, settings, exportDir) = try makeCoordinatorWithTempExport()
        defer { try? FileManager.default.removeItem(at: exportDir) }
        settings.openedImageSaveBehavior = .overwrite

        let originalURL = try writePNG(width: 5, height: 5, in: exportDir)
        let rendered = try makeTestImage(width: 9, height: 3)

        let didProceed = coordinator.handleOpenedFileSave(
            rendered, originalURL: originalURL, sourceAppName: nil, sourceWindowTitle: nil, date: Date()
        )

        XCTAssertTrue(didProceed)
        let overwritten = try XCTUnwrap(ImageFileReader.image(at: originalURL))
        XCTAssertEqual(overwritten.width, 9)
        XCTAssertEqual(overwritten.height, 3)
    }

    func testHandleOpenedFileSaveWithAskBehaviorUsesInjectedPromptOverwrite() throws {
        let (coordinator, settings, exportDir) = try makeCoordinatorWithTempExport()
        defer { try? FileManager.default.removeItem(at: exportDir) }
        settings.openedImageSaveBehavior = .ask
        coordinator.saveChoicePrompt = { _ in .overwrite }

        let originalURL = try writePNG(width: 5, height: 5, in: exportDir)
        let rendered = try makeTestImage(width: 7, height: 2)

        let didProceed = coordinator.handleOpenedFileSave(
            rendered, originalURL: originalURL, sourceAppName: nil, sourceWindowTitle: nil, date: Date()
        )

        XCTAssertTrue(didProceed)
        let overwritten = try XCTUnwrap(ImageFileReader.image(at: originalURL))
        XCTAssertEqual(overwritten.width, 7)
        XCTAssertEqual(overwritten.height, 2)
    }

    func testHandleOpenedFileSaveWithAskBehaviorUsesInjectedPromptSaveAsCopy() throws {
        let (coordinator, settings, exportDir) = try makeCoordinatorWithTempExport()
        defer { try? FileManager.default.removeItem(at: exportDir) }
        settings.openedImageSaveBehavior = .ask
        coordinator.saveChoicePrompt = { _ in .saveAsCopy }

        let originalURL = try writePNG(width: 5, height: 5, in: exportDir)
        let originalData = try Data(contentsOf: originalURL)
        let rendered = try makeTestImage(width: 6, height: 6)

        let before = try FileManager.default.contentsOfDirectory(at: exportDir, includingPropertiesForKeys: nil)
        let didProceed = coordinator.handleOpenedFileSave(
            rendered, originalURL: originalURL, sourceAppName: nil, sourceWindowTitle: nil, date: Date()
        )
        let after = try FileManager.default.contentsOfDirectory(at: exportDir, includingPropertiesForKeys: nil)

        XCTAssertTrue(didProceed)
        XCTAssertEqual(after.count, before.count + 1)
        XCTAssertEqual(try Data(contentsOf: originalURL), originalData)
    }

    func testHandleOpenedFileSaveWithAskBehaviorCancelLeavesEverythingUntouched() throws {
        let (coordinator, settings, exportDir) = try makeCoordinatorWithTempExport()
        defer { try? FileManager.default.removeItem(at: exportDir) }
        settings.openedImageSaveBehavior = .ask
        coordinator.saveChoicePrompt = { _ in .cancel }

        let originalURL = try writePNG(width: 5, height: 5, in: exportDir)
        let originalData = try Data(contentsOf: originalURL)
        let rendered = try makeTestImage(width: 6, height: 6)

        let before = try FileManager.default.contentsOfDirectory(at: exportDir, includingPropertiesForKeys: nil)
        let didProceed = coordinator.handleOpenedFileSave(
            rendered, originalURL: originalURL, sourceAppName: nil, sourceWindowTitle: nil, date: Date()
        )
        let after = try FileManager.default.contentsOfDirectory(at: exportDir, includingPropertiesForKeys: nil)

        XCTAssertFalse(didProceed)
        XCTAssertEqual(after.count, before.count)
        XCTAssertEqual(try Data(contentsOf: originalURL), originalData)
    }

    // MARK: - Helpers

    private func makeCoordinatorWithTempExport() throws -> (CaptureCoordinator, AppSettings, URL) {
        let suiteName = "OpenedImageSaveTests.\(UUID().uuidString)"
        let settings = AppSettings(defaults: UserDefaults(suiteName: suiteName)!)
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-openedimagesave-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        settings.setExportLocation(exportDir)
        let coordinator = CaptureCoordinator(settings: settings)
        return (coordinator, settings, exportDir)
    }

    private func makeTestImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func writePNG(width: Int, height: Int, in directory: URL) throws -> URL {
        let image = try makeTestImage(width: width, height: height)
        let url = directory.appendingPathComponent("original-\(UUID().uuidString)").appendingPathExtension("png")
        let data = try XCTUnwrap(ImageUtilities.pngData(from: image))
        try data.write(to: url)
        return url
    }
}
