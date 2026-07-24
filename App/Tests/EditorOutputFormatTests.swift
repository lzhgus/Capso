import XCTest
@testable import Capso

final class EditorOutputFormatTests: XCTestCase {
    func testGIFUsesGIFSaveAndExportConfiguration() {
        let format = EditorOutputFormat(recordingFormat: .gif)

        XCTAssertEqual(format, .gif)
        XCTAssertEqual(format.defaultFilename, "Recording.gif")
        XCTAssertEqual(format.fileExtension, "gif")
        XCTAssertEqual(format.contentType.identifier, "com.compuserve.gif")
        XCTAssertEqual(format.exportFormat.rawValue, "gif")
    }

    func testVideoUsesMP4SaveAndExportConfiguration() {
        let format = EditorOutputFormat(recordingFormat: .video)

        XCTAssertEqual(format, .mp4)
        XCTAssertEqual(format.defaultFilename, "Recording.mp4")
        XCTAssertEqual(format.fileExtension, "mp4")
        XCTAssertEqual(format.contentType.identifier, "public.mpeg-4")
        XCTAssertEqual(format.exportFormat.rawValue, "mp4")
    }
}
