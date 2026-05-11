// Packages/EditorKit/Sources/EditorKit/TrimRegion.swift

import Foundation

/// Represents a region of the video timeline that has been trimmed (removed).
public struct TrimRegion: Codable, Sendable, Identifiable {
    public struct TimeRange: Sendable, Equatable {
        public var start: TimeInterval
        public var end: TimeInterval

        public init(start: TimeInterval, end: TimeInterval) {
            self.start = start
            self.end = end
        }

        public var duration: TimeInterval {
            end - start
        }
    }

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

    public static func keptRanges(
        duration: TimeInterval,
        removing regions: [TrimRegion]
    ) -> [TimeRange] {
        guard duration > 0 else { return [] }

        let cuts = regions
            .map { region in
                TimeRange(
                    start: max(0, min(duration, region.startTime)),
                    end: max(0, min(duration, region.endTime))
                )
            }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }

        guard !cuts.isEmpty else {
            return [TimeRange(start: 0, end: duration)]
        }

        var merged: [TimeRange] = []
        for cut in cuts {
            guard var last = merged.last else {
                merged.append(cut)
                continue
            }

            if cut.start <= last.end {
                last.end = max(last.end, cut.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(cut)
            }
        }

        var kept: [TimeRange] = []
        var cursor: TimeInterval = 0
        for cut in merged {
            if cut.start > cursor {
                kept.append(TimeRange(start: cursor, end: cut.start))
            }
            cursor = max(cursor, cut.end)
        }

        if cursor < duration {
            kept.append(TimeRange(start: cursor, end: duration))
        }

        return kept
    }
}
