import SharedKit
import XCTest

final class RecordingClipboardStateReuseTests: XCTestCase {
    func testFinishedAutomaticCopyCanBeRestoredWithoutReencoding() throws {
        var state = RecordingClipboardState()
        XCTAssertFalse(state.canReuseAutomaticCopy)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingClipboardStateReuseTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("capso_clipboard.mp4")
        try Data([0x00, 0x01]).write(to: fileURL)
        state.markCopied(fileURL)

        XCTAssertTrue(state.canReuseAutomaticCopy)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RecordingClipboardStateReuseTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(RecordingClipboard.copy(
            fileURL: try XCTUnwrap(state.copiedFileURL),
            cleaningDirectory: directory,
            pasteboard: pasteboard
        ))

        let copied = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        XCTAssertEqual(copied, [fileURL])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
