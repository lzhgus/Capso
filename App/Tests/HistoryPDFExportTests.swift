import AppKit
import PDFKit
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
