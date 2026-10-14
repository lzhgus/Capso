import HistoryKit
import XCTest
@testable import Capso

final class HistoryRecordingSourceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func entry(_ mode: HistoryCaptureMode) -> HistoryEntry {
        HistoryEntry(captureMode: mode, imageWidth: 0, imageHeight: 0, thumbnailFileName: "thumbnail.jpg", fullImageFileName: "rec.mp4", fileSize: 0)
    }

    func testReadsCursorDataAndInfoSavedNextToTheVideo() throws {
        let info = HistoryRecordingInfo(showsCursor: false, recordingAreaWidth: 1440, recordingAreaHeight: 900)
        try JSONEncoder().encode(info).write(to: dir.appendingPathComponent(HistoryRecordingSource.infoFileName))
        try Data("{}".utf8).write(to: dir.appendingPathComponent(HistoryRecordingSource.cursorFileName))

        let source = HistoryRecordingSource(entry: entry(.gif), videoURL: dir.appendingPathComponent("rec.mp4"))
        XCTAssertEqual(source.info, info)
        XCTAssertEqual(source.cursorTelemetryURL?.lastPathComponent, HistoryRecordingSource.cursorFileName)
        XCTAssertEqual(source.mode, .gif)
    }

    func testOlderRecordingsOpenWithoutExtras() {
        let source = HistoryRecordingSource(entry: entry(.recording), videoURL: dir.appendingPathComponent("rec.mp4"))
        XCTAssertNil(source.info)
        XCTAssertNil(source.cursorTelemetryURL)
    }
}
