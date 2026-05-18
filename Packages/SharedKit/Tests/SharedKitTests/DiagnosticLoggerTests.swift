import Foundation
import Testing
@testable import SharedKit

@Suite("DiagnosticLogger")
struct DiagnosticLoggerTests {
    @Test("append writes timestamped diagnostic lines")
    func appendWritesLine() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-diagnostic-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("capso.log")
        defer { try? FileManager.default.removeItem(at: directory) }

        DiagnosticLogger.append("hello diagnostics", category: "Test", fileURL: fileURL)

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(contents.contains("[Test] hello diagnostics"))
    }

    @Test("prepare log file creates an empty selectable file")
    func prepareLogFileCreatesFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-diagnostic-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("capso.log")
        defer { try? FileManager.default.removeItem(at: directory) }

        let preparedURL = DiagnosticLogger.prepareLogFile(at: fileURL)

        #expect(preparedURL == fileURL)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(contents.isEmpty)
    }
}
