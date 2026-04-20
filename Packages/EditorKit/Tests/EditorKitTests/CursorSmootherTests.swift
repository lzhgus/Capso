// Packages/EditorKit/Tests/EditorKitTests/CursorSmootherTests.swift

import Testing
@testable import EditorKit
import EffectsKit

@Suite("CursorSmoother")
struct CursorSmootherTests {

    // MARK: - Helper

    private func makeTelemetry() -> CursorTelemetryData {
        CursorTelemetryData(
            recordingAreaWidth: 1280,
            recordingAreaHeight: 720,
            events: [
                CursorEvent(timestamp: 0.0, x: 0.1, y: 0.1, type: .move),
                CursorEvent(timestamp: 0.5, x: 0.5, y: 0.5, type: .move),
                CursorEvent(timestamp: 1.0, x: 0.5, y: 0.5, type: .leftClick),
                CursorEvent(timestamp: 1.5, x: 0.9, y: 0.9, type: .move),
                CursorEvent(timestamp: 2.0, x: 0.9, y: 0.1, type: .move),
            ]
        )
    }

    // MARK: - Raw position tests

    @Test("Raw position interpolates linearly between events")
    func rawPositionInterpolatesLinearly() {
        let telemetry = CursorTelemetryData(
            recordingAreaWidth: 1280,
            recordingAreaHeight: 720,
            events: [
                CursorEvent(timestamp: 0.0, x: 0.1, y: 0.1, type: .move),
                CursorEvent(timestamp: 0.1, x: 0.5, y: 0.5, type: .move),
            ]
        )
        let smoother = CursorSmoother(
            telemetry: telemetry,
            config: .smooth
        )
        // At t=0.05: midpoint between (0.1,0.1) at t=0.0 and (0.5,0.5) at t=0.1
        // fraction = (0.05 - 0.0) / (0.1 - 0.0) = 0.5
        // x = 0.1 + 0.5*(0.5-0.1) = 0.3, y = 0.1 + 0.5*(0.5-0.1) = 0.3
        let pos = smoother.rawPosition(at: 0.05)
        #expect(abs(pos.x - 0.3) < 1e-10)
        #expect(abs(pos.y - 0.3) < 1e-10)
    }

    @Test("Raw position holds steady across long telemetry gaps")
    func rawPositionHoldsAcrossLongGap() {
        let telemetry = CursorTelemetryData(
            recordingAreaWidth: 1280,
            recordingAreaHeight: 720,
            events: [
                CursorEvent(timestamp: 0.0, x: 0.2, y: 0.2, type: .move),
                CursorEvent(timestamp: 2.0, x: 0.8, y: 0.8, type: .move),
            ]
        )

        let smoother = CursorSmoother(
            telemetry: telemetry,
            config: .smooth
        )

        let pos = smoother.rawPosition(at: 1.0)
        #expect(abs(pos.x - 0.2) < 1e-10)
        #expect(abs(pos.y - 0.2) < 1e-10)
    }

    @Test("Raw position clamps before first event")
    func rawPositionClampsBeforeFirst() {
        let smoother = CursorSmoother(
            telemetry: makeTelemetry(),
            config: .smooth
        )
        let pos = smoother.rawPosition(at: -1.0)
        #expect(abs(pos.x - 0.1) < 1e-10)
        #expect(abs(pos.y - 0.1) < 1e-10)
    }

    @Test("Raw position clamps after last event")
    func rawPositionClampsAfterLast() {
        let smoother = CursorSmoother(
            telemetry: makeTelemetry(),
            config: .smooth
        )
        let pos = smoother.rawPosition(at: 99.0)
        #expect(abs(pos.x - 0.9) < 1e-10)
        #expect(abs(pos.y - 0.1) < 1e-10)
    }

    // MARK: - Smoothed timeline tests

    @Test("Smoothed position lags behind raw position")
    func smoothedPositionLagsBehindRaw() {
        let smoother = CursorSmoother(
            telemetry: makeTelemetry(),
            config: .smooth        // enabled = true
        )
        let timeline = smoother.buildSmoothedTimeline(fps: 60, duration: 2.0)
        let raw = smoother.rawPosition(at: 0.5)
        let smoothed = timeline.position(at: 0.5)
        // Smoothing introduces lag — smoothed position must differ from raw at t=0.5
        let distanceX = abs(smoothed.x - raw.x)
        let distanceY = abs(smoothed.y - raw.y)
        #expect(distanceX > 1e-4 || distanceY > 1e-4)
    }

    @Test("Smoothed timeline has expected sample count")
    func smoothedTimelineHasExpectedSampleCount() {
        let smoother = CursorSmoother(
            telemetry: makeTelemetry(),
            config: .smooth
        )
        // 2.0 seconds at 60 fps: samples at t = 0, 1/60, 2/60, ..., 120/60
        // count = floor(2.0 / (1/60)) + 1 = floor(120.0) + 1 = 121
        let timeline = smoother.buildSmoothedTimeline(fps: 60, duration: 2.0)
        #expect(timeline.sampleCount == 121)
    }

    @Test("Click events are preserved")
    func clickEventsArePreserved() {
        let smoother = CursorSmoother(
            telemetry: makeTelemetry(),
            config: .smooth
        )
        let clicks = smoother.clickEvents()
        // Only one leftClick at t=1.0 in the test telemetry
        #expect(clicks.count == 1)
        #expect(clicks[0].type == .leftClick)
        #expect(abs(clicks[0].timestamp - 1.0) < 1e-10)
    }

    @Test("Disabled smoothing returns raw positions")
    func disabledSmoothingReturnsRawPositions() {
        var disabledConfig = CursorSmoothingConfig.smooth
        disabledConfig.enabled = false

        let smoother = CursorSmoother(
            telemetry: makeTelemetry(),
            config: disabledConfig
        )
        let timeline = smoother.buildSmoothedTimeline(fps: 60, duration: 2.0)

        // Every sample in the timeline must exactly match rawPosition at that time.
        let dt = 1.0 / 60.0
        for i in 0..<timeline.sampleCount {
            let t = Double(i) * dt
            let raw      = smoother.rawPosition(at: t)
            let smoothed = timeline.position(at: t)
            #expect(abs(smoothed.x - raw.x) < 1e-10,
                    "x mismatch at sample \(i) (t=\(t)): smoothed=\(smoothed.x) raw=\(raw.x)")
            #expect(abs(smoothed.y - raw.y) < 1e-10,
                    "y mismatch at sample \(i) (t=\(t)): smoothed=\(smoothed.y) raw=\(raw.y)")
        }
    }
}
