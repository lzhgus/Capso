import Testing
import Foundation
@testable import RecordingKit

@Suite("ScreenRecorder disk space")
@MainActor
struct ScreenRecorderDiskSpaceTests {
    private func makeRecorder(freeBytes: Int64?) -> (ScreenRecorder, () -> Int) {
        let recorder = ScreenRecorder()
        recorder.state = .recording
        recorder.availableDiskBytes = { _ in freeBytes }
        var reports = 0
        recorder.onDiskSpaceLow = { reports += 1 }
        return (recorder, { reports })
    }

    @Test("Enough free space never stops the recording")
    func enoughSpace() {
        let (recorder, reports) = makeRecorder(freeBytes: DiskSpace.minimumToKeepRecording)
        for second in stride(from: 0.0, through: 60, by: 0.5) {
            recorder.checkDiskSpaceIfDue(elapsed: second)
        }
        #expect(reports() == 0)
    }

    @Test("Low space is reported once, on the first check after the interval")
    func lowSpaceReportedOnce() {
        let (recorder, reports) = makeRecorder(freeBytes: DiskSpace.minimumToKeepRecording - 1)

        recorder.checkDiskSpaceIfDue(elapsed: ScreenRecorder.diskSpaceCheckInterval - 0.1)
        #expect(reports() == 0)

        recorder.checkDiskSpaceIfDue(elapsed: ScreenRecorder.diskSpaceCheckInterval)
        recorder.checkDiskSpaceIfDue(elapsed: ScreenRecorder.diskSpaceCheckInterval * 3)
        #expect(reports() == 1)
    }

    @Test("Paused recordings and unknown free space are not reported")
    func pausedOrUnknown() {
        let (paused, pausedReports) = makeRecorder(freeBytes: 0)
        paused.state = .paused
        paused.checkDiskSpaceIfDue(elapsed: 60)
        #expect(pausedReports() == 0)

        let (unknown, unknownReports) = makeRecorder(freeBytes: nil)
        unknown.checkDiskSpaceIfDue(elapsed: 60)
        #expect(unknownReports() == 0)
    }

    @Test("Free space of the boot volume can be read")
    func readsRealVolume() {
        let available = DiskSpace.availableBytes(at: ScreenRecorder.recordingDirectory)
        #expect((available ?? 0) > 0)
    }
}
