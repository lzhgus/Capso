// Packages/EditorKit/Sources/EditorKit/TrimRegion.swift

import Foundation

/// Represents a region of the video timeline that has been trimmed (removed).
public struct TrimRegion: Codable, Sendable, Identifiable {
    public var id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval

    public init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
    }

    /// Duration of the trimmed region in seconds.
    public var duration: TimeInterval { endTime - startTime }
}
