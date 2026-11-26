import AppKit
import CaptureKit
import HistoryKit
import PDFKit
import SharedKit
import XCTest
@testable import Capso

final class HistoryPDFExportTests: XCTestCase {
    func testEachImageBecomesOnePageInOrder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try writePNG(width: 40, height: 20, to: dir.appendingPathComponent("a.png"))
        let second = try writePNG(width: 10, height: 30, to: dir.appendingPathComponent("b.png"))
        let missing = dir.appendingPathComponent("missing.png")
        let pdfURL = dir.appendingPathComponent("out.pdf")

        XCTAssertTrue(HistoryCoordinator.writePDF(pages: [first, missing, second], to: pdfURL))

        let document = try XCTUnwrap(PDFDocument(url: pdfURL))
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 40, height: 20))
        XCTAssertEqual(document.page(at: 1)?.bounds(for: .mediaBox).size, CGSize(width: 10, height: 30))
    }

    func testNoReadableImagesWritesNothing() {
        let pdfURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        XCTAssertFalse(HistoryCoordinator.writePDF(pages: [URL(fileURLWithPath: "/nonexistent.png")], to: pdfURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pdfURL.path))
    }

    @MainActor
    func testImportPDFInterleaveScreenshotReorderAndExportBackToPDF() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create a 2-page PDF with distinct page dimensions so order is verifiable after export.
        let p1Img = try writePNG(width: 200, height: 100, to: dir.appendingPathComponent("slide1.png"))
        let p2Img = try writePNG(width: 200, height: 150, to: dir.appendingPathComponent("slide2.png"))
        let inputPDF = dir.appendingPathComponent("Lecture.pdf")
        XCTAssertTrue(HistoryCoordinator.writePDF(pages: [p1Img, p2Img], to: inputPDF))

        let storeDir = dir.appendingPathComponent("store", isDirectory: true)
        let store = try HistoryStore(directory: storeDir)
        let settings = AppSettings()
        let coordinator = HistoryCoordinator(settings: settings, store: store)

        let importedID = await coordinator.importPDF(from: inputPDF)
        let collectionID = try XCTUnwrap(importedID)
        coordinator.openCollection(collectionID)

        XCTAssertEqual(coordinator.collections.count, 1)
        XCTAssertEqual(coordinator.collections.first?.collection.title, "Lecture")
        XCTAssertEqual(coordinator.activeCollectionEntries.count, 2)
        // PDF pages stay grouped inside the collection rather than flooding the flat timeline.
        XCTAssertTrue(coordinator.entries.isEmpty)

        // Add a regular screenshot to history and interleave it between Slide 1 and Slide 2.
        let screenshotCG = try makeCGImage(width: 120, height: 120)
        let screenshotID = UUID()
        let screenshotDir = store.entriesDirectory.appendingPathComponent(screenshotID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)
        let screenshotData = try XCTUnwrap(ImageUtilities.pngData(from: screenshotCG))
        try screenshotData.write(to: screenshotDir.appendingPathComponent("capture.png"))
        let screenshotEntry = HistoryEntry(
            id: screenshotID,
            captureMode: .area,
            imageWidth: 120,
            imageHeight: 120,
            sourceAppName: "Xcode",
            thumbnailFileName: "thumbnail.jpg",
            fullImageFileName: "capture.png",
            fileSize: Int64(screenshotData.count)
        )
        try store.insert(screenshotEntry)

        coordinator.addEntries([screenshotEntry], toCollection: collectionID, insertAt: 1)
        XCTAssertEqual(coordinator.activeCollectionEntries.count, 3)
        XCTAssertEqual(coordinator.activeCollectionEntries[1].id, screenshotID)

        // Export the interleaved deck to PDF and verify exact page order (Slide 1 -> Screenshot -> Slide 2).
        let outputPDF = dir.appendingPathComponent("Lecture_Annotated.pdf")
        XCTAssertTrue(coordinator.writeCollectionPDF(collectionID, to: outputPDF))

        let exported = try XCTUnwrap(PDFDocument(url: outputPDF))
        XCTAssertEqual(exported.pageCount, 3)
        // Page 0: Slide 1 (200x100 @ 2x = 400x200)
        XCTAssertEqual(exported.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 400, height: 200))
        // Page 1: Interleaved screenshot (120x120)
        XCTAssertEqual(exported.page(at: 1)?.bounds(for: .mediaBox).size, CGSize(width: 120, height: 120))
        // Page 2: Slide 2 (200x150 @ 2x = 400x300)
        XCTAssertEqual(exported.page(at: 2)?.bounds(for: .mediaBox).size, CGSize(width: 400, height: 300))

        // Removing the collection deletes imported .pdfPage entries but preserves regular screenshots.
        coordinator.deleteCollection(collectionID)
        XCTAssertTrue(coordinator.collections.isEmpty)
        XCTAssertEqual(try store.fetchAll(filter: .screenshots).map(\.id), [screenshotID])
    }

    private func makeCGImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func writePNG(width: Int, height: Int, to url: URL) throws -> URL {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        return url
    }
}
