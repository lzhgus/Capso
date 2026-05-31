// Packages/RecordingKit/Tests/RecordingKitTests/RecordingStateTests.swift
import Testing
import Foundation
@testable import RecordingKit

@Suite("RecordingState")
struct RecordingStateTests {
    @Test("RecordingState has expected cases")
    func states() {
        let states: [RecordingState] = [.idle, .preparing, .recording, .paused, .stopping]
        #expect(states.count == 5)
    }

    @Test("RecordingState isActive")
    func isActive() {
        #expect(RecordingState.recording.isActive == true)
        #expect(RecordingState.paused.isActive == true)
        #expect(RecordingState.idle.isActive == false)
        #expect(RecordingState.preparing.isActive == false)
        #expect(RecordingState.stopping.isActive == false)
    }

    @Test("RecordingFormat has two cases")
    func formats() {
        let formats: [RecordingFormat] = [.video, .gif]
        #expect(formats.count == 2)
    }

    @Test("RecordingConfig defaults")
    func configDefaults() {
        let rect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let config = RecordingConfig(captureRect: rect, displayID: 1)
        #expect(config.target == .displayArea(displayID: 1, rect: rect))
        #expect(config.format == .video)
        #expect(config.fps == 30)
        #expect(config.captureSystemAudio == true)
        #expect(config.captureMicrophone == false)
        #expect(config.showCursor == true)
    }

    @Test("RecordingConfig can target a window")
    func configWindowTarget() {
        let config = RecordingConfig(windowID: 42, captureSystemAudio: false)

        #expect(config.target == .window(windowID: 42))
        #expect(config.captureSystemAudio == false)
        #expect(config.captureMicrophone == false)
        #expect(config.showCursor == true)
    }
}
