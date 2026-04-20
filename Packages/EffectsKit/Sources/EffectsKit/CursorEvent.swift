// Packages/EffectsKit/Sources/EffectsKit/CursorEvent.swift

import Foundation

/// The type of cursor interaction being recorded.
public enum CursorEventType: String, Codable, Sendable {
    case move
    case leftClick
    case rightClick
}

/// A single cursor event captured during a recording session.
/// Coordinates are normalized to [0, 1] relative to the recording area.
public struct CursorEvent: Codable, Sendable {
    /// Time in seconds since recording started, relative to `start()` being called.
    public let timestamp: TimeInterval
    /// Normalized horizontal position (0 = left edge, 1 = right edge).
    public let x: Double
    /// Normalized vertical position (0 = top edge, 1 = bottom edge).
    public let y: Double
    /// The type of cursor interaction.
    public let type: CursorEventType

    public init(timestamp: TimeInterval, x: Double, y: Double, type: CursorEventType) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.type = type
    }
}

/// Container for all cursor telemetry captured during a recording session.
public struct CursorTelemetryData: Codable, Sendable {
    /// Width of the recording area in display points.
    public let recordingAreaWidth: Double
    /// Height of the recording area in display points.
    public let recordingAreaHeight: Double
    /// Ordered list of cursor events recorded during the session.
    public let events: [CursorEvent]

    public init(recordingAreaWidth: Double, recordingAreaHeight: Double, events: [CursorEvent]) {
        self.recordingAreaWidth = recordingAreaWidth
        self.recordingAreaHeight = recordingAreaHeight
        self.events = events
    }
}
