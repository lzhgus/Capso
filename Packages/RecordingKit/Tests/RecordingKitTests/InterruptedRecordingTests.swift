import Testing
import Foundation
@testable import RecordingKit

@Suite("Interrupted recording marker")
struct InterruptedRecordingTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "InterruptedRecordingTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    private func makeFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("interrupted_\(UUID().uuidString).mov")
        try Data([0]).write(to: url)
        return url
    }

    @Test("Nothing to recover when no recording was marked")
    func emptyByDefault() {
        #expect(InterruptedRecording.take(defaults: makeDefaults()) == nil)
    }

    @Test("A marked recording is returned once")
    func markedFileIsReturnedOnce() throws {
        let defaults = makeDefaults()
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }

        InterruptedRecording.mark(file, defaults: defaults)

        #expect(InterruptedRecording.take(defaults: defaults)?.path == file.path)
        #expect(InterruptedRecording.take(defaults: defaults) == nil)
    }

    @Test("A finished recording is not recovered")
    func clearedMarkerIsIgnored() throws {
        let defaults = makeDefaults()
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }

        InterruptedRecording.mark(file, defaults: defaults)
        InterruptedRecording.clear(defaults: defaults)

        #expect(InterruptedRecording.take(defaults: defaults) == nil)
    }

    @Test("A marked file that no longer exists is dropped")
    func missingFileIsDropped() {
        let defaults = makeDefaults()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing_\(UUID().uuidString).mov")

        InterruptedRecording.mark(missing, defaults: defaults)

        #expect(InterruptedRecording.take(defaults: defaults) == nil)
        #expect(defaults.string(forKey: InterruptedRecording.key) == nil)
    }
}
