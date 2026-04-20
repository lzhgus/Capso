// Packages/EditorKit/Sources/EditorKit/ZoomSegment.swift

import Foundation

/// Determines how the zoom focus point is calculated during a zoom segment.
public enum ZoomFocusMode: Codable, Sendable, Equatable {
    /// The zoom center tracks the cursor position in real time.
    case followCursor
    /// The zoom is locked to a fixed normalized position (0–1 range).
    case manual(x: Double, y: Double)
}

/// Indicates whether a zoom segment was created by the user or by AutoZoomDetector.
public enum SegmentSource: String, Codable, Sendable {
    case manual
    case auto
}

/// A time-bounded segment of the video that applies a zoom effect.
public struct ZoomSegment: Codable, Sendable, Identifiable {
    public var id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    /// Zoom magnification level. 1.0 = no zoom, 2.0 = 2× magnification.
    public var zoomLevel: Double
    /// How the zoom focus point is determined.
    public var focusMode: ZoomFocusMode
    /// How this segment was created.
    public var source: SegmentSource

    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        zoomLevel: Double = 1.5,
        focusMode: ZoomFocusMode = .followCursor,
        source: SegmentSource = .manual
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.zoomLevel = zoomLevel
        self.focusMode = focusMode
        self.source = source
    }

    /// Duration of the zoom segment in seconds.
    public var duration: TimeInterval { endTime - startTime }

    // Legacy JSON written before Phase 2.1 lacks the `source` key. Swift's
    // synthesized init(from:) throws keyNotFound regardless of property
    // defaults, so we override it to decode `source` as optional.
    private enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, zoomLevel, focusMode, source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.startTime = try c.decode(TimeInterval.self, forKey: .startTime)
        self.endTime = try c.decode(TimeInterval.self, forKey: .endTime)
        self.zoomLevel = try c.decode(Double.self, forKey: .zoomLevel)
        self.focusMode = try c.decode(ZoomFocusMode.self, forKey: .focusMode)
        self.source = try c.decodeIfPresent(SegmentSource.self, forKey: .source) ?? .manual
    }
}
