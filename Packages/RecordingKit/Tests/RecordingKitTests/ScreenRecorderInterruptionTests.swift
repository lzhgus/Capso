import Testing
import Foundation
@testable import RecordingKit

@Suite("ScreenRecorder interruption")
@MainActor
struct ScreenRecorderInterruptionTests {
    private struct StreamStopped: Error {}

    @Test("Stream stop while idle is ignored")
    func streamStopWhileIdleIsIgnored() {
        let recorder = ScreenRecorder()
        var interruptions = 0
        recorder.onStreamInterrupted = { _ in interruptions += 1 }

        recorder.handleStreamStopped(error: StreamStopped())

        #expect(interruptions == 0)
        #expect(recorder.state == .idle)
    }

    @Test("Stream stop while recording notifies the owner once")
    func streamStopWhileRecordingNotifiesOnce() {
        let recorder = ScreenRecorder()
        var interruptions = 0
        recorder.onStreamInterrupted = { _ in interruptions += 1 }
        recorder.state = .recording

        recorder.handleStreamStopped(error: StreamStopped())
        recorder.handleStreamStopped(error: StreamStopped())

        #expect(interruptions == 1)
    }

    @Test("Stream stop while paused notifies the owner")
    func streamStopWhilePausedNotifies() {
        let recorder = ScreenRecorder()
        var interruptions = 0
        recorder.onStreamInterrupted = { _ in interruptions += 1 }
        recorder.state = .paused

        recorder.handleStreamStopped(error: StreamStopped())

        #expect(interruptions == 1)
    }

    @Test("Stopping after an interruption always returns to idle")
    func stopAfterInterruptionResetsToIdle() async {
        let recorder = ScreenRecorder()
        recorder.onStreamInterrupted = { _ in }
        recorder.state = .recording
        recorder.handleStreamStopped(error: StreamStopped())

        do {
            _ = try await recorder.stopRecording()
            Issue.record("Expected stopRecording to throw when nothing was written")
        } catch RecordingError.noFramesCaptured {
            // Expected: no frames were captured before the stream stopped.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(recorder.state == .idle)

        // A fresh recording session can be interrupted (and reported) again.
        var interruptions = 0
        recorder.onStreamInterrupted = { _ in interruptions += 1 }
        recorder.state = .recording
        recorder.handleStreamStopped(error: StreamStopped())
        #expect(interruptions == 1)
    }
}
