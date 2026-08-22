import AppKit
import Foundation
import Testing
@testable import SharedKit

@Suite("RecordingClipboard")
struct RecordingClipboardTests {
    @Test("copies a readable recording as a file URL")
    func copiesReadableRecording() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-recording-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        try Data([0x00, 0x01]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let pasteboard = makePasteboard()

        #expect(RecordingClipboard.copy(fileURL: fileURL, pasteboard: pasteboard))

        let copiedURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        #expect(copiedURLs == [fileURL])
    }

    @Test("does not replace the clipboard for a missing recording")
    func rejectsMissingRecording() {
        let pasteboard = makePasteboard()
        pasteboard.setString("keep me", forType: .string)
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).gif")

        #expect(!RecordingClipboard.copy(fileURL: missingURL, pasteboard: pasteboard))
        #expect(pasteboard.string(forType: .string) == "keep me")
    }

    @Test("removes superseded managed exports after copying")
    func removesSupersededExports() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingClipboardTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let currentURL = directory.appendingPathComponent("current.mp4")
        let staleURL = directory.appendingPathComponent("stale.gif")
        try Data([0x00]).write(to: currentURL)
        try Data([0x01]).write(to: staleURL)

        #expect(RecordingClipboard.copy(
            fileURL: currentURL,
            cleaningDirectory: directory,
            pasteboard: makePasteboard()
        ))
        #expect(FileManager.default.fileExists(atPath: currentURL.path))
        #expect(!FileManager.default.fileExists(atPath: staleURL.path))
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("RecordingClipboardTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        return pasteboard
    }
}
