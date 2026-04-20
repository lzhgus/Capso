// Packages/EffectsKit/Tests/EffectsKitTests/CursorTelemetryTests.swift

import Testing
import Foundation
import CoreGraphics
@testable import EffectsKit

@Suite("CursorEvent model")
struct CursorEventModelTests {

    @Test("CursorEvent encodes and decodes correctly")
    func cursorEventRoundTrip() throws {
        let original = CursorEvent(timestamp: 1.5, x: 0.25, y: 0.75, type: .leftClick)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CursorEvent.self, from: data)

        #expect(decoded.timestamp == original.timestamp)
        #expect(decoded.x == original.x)
        #expect(decoded.y == original.y)
        #expect(decoded.type == original.type)
    }

    @Test("CursorEventType raw values are stable")
    func cursorEventTypeRawValues() {
        #expect(CursorEventType.move.rawValue == "move")
        #expect(CursorEventType.leftClick.rawValue == "leftClick")
        #expect(CursorEventType.rightClick.rawValue == "rightClick")
    }

    @Test("CursorTelemetryData encodes and decodes with multiple events")
    func telemetryDataRoundTrip() throws {
        let events: [CursorEvent] = [
            CursorEvent(timestamp: 0.0, x: 0.0, y: 0.0, type: .move),
            CursorEvent(timestamp: 1.0, x: 0.5, y: 0.5, type: .leftClick),
            CursorEvent(timestamp: 2.0, x: 1.0, y: 1.0, type: .rightClick),
        ]
        let original = CursorTelemetryData(
            recordingAreaWidth: 1920,
            recordingAreaHeight: 1080,
            events: events
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CursorTelemetryData.self, from: data)

        #expect(decoded.recordingAreaWidth == 1920)
        #expect(decoded.recordingAreaHeight == 1080)
        #expect(decoded.events.count == 3)
        #expect(decoded.events[1].type == .leftClick)
        #expect(decoded.events[2].x == 1.0)
    }
}

@Suite("CursorTelemetry normalization")
struct CursorTelemetryNormalizationTests {

    /// Recording area: 100×200 pt at origin (0, 0) in display coords.
    private func makeTelemetry(rect: CGRect = CGRect(x: 0, y: 0, width: 100, height: 200)) -> CursorTelemetry {
        CursorTelemetry(recordingRect: rect)
    }

    @Test("Normalizes a point at the top-left corner")
    func normalizeTopLeft() {
        let telemetry = makeTelemetry()
        let result = telemetry.normalize(globalPoint: CGPoint(x: 0, y: 0))
        #expect(result.x == 0.0)
        #expect(result.y == 0.0)
    }

    @Test("Normalizes a point at the bottom-right corner")
    func normalizeBottomRight() {
        let telemetry = makeTelemetry()
        let result = telemetry.normalize(globalPoint: CGPoint(x: 100, y: 200))
        #expect(result.x == 1.0)
        #expect(result.y == 1.0)
    }

    @Test("Normalizes a centered point")
    func normalizeCenter() {
        let telemetry = makeTelemetry()
        let result = telemetry.normalize(globalPoint: CGPoint(x: 50, y: 100))
        #expect(abs(result.x - 0.5) < 1e-10)
        #expect(abs(result.y - 0.5) < 1e-10)
    }

    @Test("Normalizes relative to non-zero rect origin")
    func normalizeWithOffset() {
        let rect = CGRect(x: 200, y: 300, width: 400, height: 600)
        let telemetry = CursorTelemetry(recordingRect: rect)
        // Global point at center of the rect
        let result = telemetry.normalize(globalPoint: CGPoint(x: 400, y: 600))
        #expect(abs(result.x - 0.5) < 1e-10)
        #expect(abs(result.y - 0.5) < 1e-10)
    }

    @Test("Clamps a point to the left of the recording area")
    func clampLeft() {
        let telemetry = makeTelemetry()
        let result = telemetry.normalize(globalPoint: CGPoint(x: -50, y: 100))
        #expect(result.x == 0.0)
        #expect(abs(result.y - 0.5) < 1e-10)
    }

    @Test("Clamps a point to the right of the recording area")
    func clampRight() {
        let telemetry = makeTelemetry()
        let result = telemetry.normalize(globalPoint: CGPoint(x: 200, y: 100))
        #expect(result.x == 1.0)
    }

    @Test("Clamps a point above the recording area")
    func clampTop() {
        let telemetry = makeTelemetry()
        let result = telemetry.normalize(globalPoint: CGPoint(x: 50, y: -100))
        #expect(result.y == 0.0)
    }

    @Test("Clamps a point below the recording area")
    func clampBottom() {
        let telemetry = makeTelemetry()
        let result = telemetry.normalize(globalPoint: CGPoint(x: 50, y: 400))
        #expect(result.y == 1.0)
    }
}

@Suite("CursorTelemetry data collection and export")
struct CursorTelemetryExportTests {

    @Test("exportData returns correct event count and normalized coords")
    func exportData() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let telemetry = CursorTelemetry(recordingRect: rect)

        telemetry.addEvent(timestamp: 0.0, globalPoint: CGPoint(x: 100, y: 50), type: .move)
        telemetry.addEvent(timestamp: 0.5, globalPoint: CGPoint(x: 0, y: 0), type: .leftClick)
        telemetry.addEvent(timestamp: 1.0, globalPoint: CGPoint(x: 200, y: 100), type: .rightClick)

        let data = telemetry.exportData()

        #expect(data.events.count == 3)
        #expect(data.recordingAreaWidth == 200)
        #expect(data.recordingAreaHeight == 100)

        // Center point should normalize to 0.5, 0.5
        #expect(abs(data.events[0].x - 0.5) < 1e-10)
        #expect(abs(data.events[0].y - 0.5) < 1e-10)

        // Top-left corner
        #expect(data.events[1].x == 0.0)
        #expect(data.events[1].y == 0.0)

        // Bottom-right corner
        #expect(data.events[2].x == 1.0)
        #expect(data.events[2].y == 1.0)
    }

    @Test("exportData preserves timestamps")
    func exportDataTimestamps() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let telemetry = CursorTelemetry(recordingRect: rect)

        telemetry.addEvent(timestamp: 0.123, globalPoint: CGPoint(x: 50, y: 50), type: .move)
        telemetry.addEvent(timestamp: 4.567, globalPoint: CGPoint(x: 50, y: 50), type: .leftClick)

        let data = telemetry.exportData()
        #expect(data.events[0].timestamp == 0.123)
        #expect(data.events[1].timestamp == 4.567)
    }

    @Test("exportData is empty when no events were added")
    func exportDataEmpty() {
        let telemetry = CursorTelemetry(recordingRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        let data = telemetry.exportData()
        #expect(data.events.isEmpty)
    }

    @Test("save and load round-trips telemetry data via JSON")
    func saveAndLoad() throws {
        let rect = CGRect(x: 0, y: 0, width: 640, height: 480)
        let telemetry = CursorTelemetry(recordingRect: rect)
        telemetry.addEvent(timestamp: 0.1, globalPoint: CGPoint(x: 320, y: 240), type: .move)
        telemetry.addEvent(timestamp: 0.2, globalPoint: CGPoint(x: 100, y: 100), type: .leftClick)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        try telemetry.save(to: url)
        let loaded = try CursorTelemetry.load(from: url)

        #expect(loaded.recordingAreaWidth == 640)
        #expect(loaded.recordingAreaHeight == 480)
        #expect(loaded.events.count == 2)
        #expect(loaded.events[0].type == .move)
        #expect(loaded.events[1].type == .leftClick)

        try? FileManager.default.removeItem(at: url)
    }
}
