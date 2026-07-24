import AppKit
import XCTest
import SharedKit
@testable import Capso

@MainActor
final class OpenImageFileTests: XCTestCase {
    func testInfoPlistDeclaresImageDocumentTypes() throws {
        let types = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]]
        )
        let imageEntry = try XCTUnwrap(types.first { entry in
            (entry["LSItemContentTypes"] as? [String])?.contains("public.png") == true
        })

        let contentTypes = try XCTUnwrap(imageEntry["LSItemContentTypes"] as? [String])
        for expected in ["public.png", "public.jpeg", "public.heic", "public.tiff", "com.compuserve.gif"] {
            XCTAssertTrue(contentTypes.contains(expected), "missing \(expected)")
        }
        XCTAssertEqual(imageEntry["CFBundleTypeRole"] as? String, "Editor")
        XCTAssertEqual(imageEntry["LSHandlerRank"] as? String, "Alternate")
    }

    // MARK: - openImageFiles

    func testOpenImageFilesShowsAnnotationEditorForValidPNG() throws {
        let coordinator = makeCoordinator()
        let url = try writePNG(width: 4, height: 4)
        defer {
            try? FileManager.default.removeItem(at: url)
            coordinator.annotationWindow?.close()
        }

        let result = coordinator.openImageFiles([url])

        XCTAssertTrue(result)
        XCTAssertNotNil(coordinator.annotationWindow)
    }

    func testOpenImageFilesReturnsFalseForCorruptFile() throws {
        let coordinator = makeCoordinator()
        let url = try writeCorruptFile(extension: "png")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = coordinator.openImageFiles([url])

        XCTAssertFalse(result)
        XCTAssertNil(coordinator.annotationWindow)
    }

    func testOpenImageFilesReturnsFalseForEmptyList() {
        let coordinator = makeCoordinator()

        let result = coordinator.openImageFiles([])

        XCTAssertFalse(result)
        XCTAssertNil(coordinator.annotationWindow)
    }

    func testOpenImageFilesOpensFirstLoadableAndSkipsRest() throws {
        let coordinator = makeCoordinator()
        let corrupt = try writeCorruptFile(extension: "png")
        let goodA = try writePNG(width: 7, height: 5)
        let goodB = try writePNG(width: 3, height: 3)
        defer {
            try? FileManager.default.removeItem(at: corrupt)
            try? FileManager.default.removeItem(at: goodA)
            try? FileManager.default.removeItem(at: goodB)
            coordinator.annotationWindow?.close()
        }

        let result = coordinator.openImageFiles([corrupt, goodA, goodB])

        XCTAssertTrue(result)
        let window = try XCTUnwrap(coordinator.annotationWindow)
        XCTAssertEqual(window.document.imageSize, CGSize(width: 7, height: 5))
    }

    func testOpenImageFilesWithPanelUsesInjectedProvider() throws {
        let coordinator = makeCoordinator()
        let url = try writePNG(width: 6, height: 6)
        defer {
            try? FileManager.default.removeItem(at: url)
            coordinator.annotationWindow?.close()
        }
        coordinator.openPanelURLsProvider = { [url] }

        coordinator.openImageFilesWithPanel()

        XCTAssertNotNil(coordinator.annotationWindow)
    }

    // MARK: - Helpers

    private func makeCoordinator() -> CaptureCoordinator {
        let suiteName = "OpenImageFileTests.\(UUID().uuidString)"
        let settings = AppSettings(defaults: UserDefaults(suiteName: suiteName)!)
        return CaptureCoordinator(settings: settings)
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
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func writePNG(width: Int, height: Int) throws -> URL {
        let image = try makeTestImage(width: width, height: height)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-openimage-\(UUID().uuidString)")
            .appendingPathExtension("png")
        let data = try XCTUnwrap(ImageUtilities.pngData(from: image))
        try data.write(to: url)
        return url
    }

    private func writeCorruptFile(extension ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-openimage-corrupt-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: url)
        return url
    }
}
