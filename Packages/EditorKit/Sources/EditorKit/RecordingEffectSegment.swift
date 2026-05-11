import CoreGraphics
import Foundation

public struct RecordingEffectSegment: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var source: SegmentSource
    public var payload: RecordingEffectPayload

    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        source: SegmentSource = .manual,
        payload: RecordingEffectPayload
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.source = source
        self.payload = payload
    }

    public init(zoom: ZoomSegment) {
        self.init(
            id: zoom.id,
            startTime: zoom.startTime,
            endTime: zoom.endTime,
            source: zoom.source,
            payload: .zoom(
                ZoomEffectPayload(
                    zoomLevel: zoom.zoomLevel,
                    focusMode: zoom.focusMode
                )
            )
        )
    }

    public var duration: TimeInterval {
        endTime - startTime
    }

    public var kind: RecordingEffectKind {
        payload.kind
    }

    public var zoomSegment: ZoomSegment? {
        guard case .zoom(let zoom) = payload else { return nil }
        return ZoomSegment(
            id: id,
            startTime: startTime,
            endTime: endTime,
            zoomLevel: zoom.zoomLevel,
            focusMode: zoom.focusMode,
            source: source
        )
    }

    public func contains(_ time: TimeInterval) -> Bool {
        time >= startTime && time <= endTime
    }
}

public enum RecordingEffectKind: String, Codable, Sendable, CaseIterable {
    case zoom
    case blur

    public var displayName: String {
        switch self {
        case .zoom: "Zoom"
        case .blur: "Blur"
        }
    }
}

public enum RecordingEffectPayload: Codable, Sendable, Equatable {
    case zoom(ZoomEffectPayload)
    case blur(BlurEffectPayload)

    public var kind: RecordingEffectKind {
        switch self {
        case .zoom: .zoom
        case .blur: .blur
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(RecordingEffectKind.self, forKey: .type)

        switch type {
        case .zoom:
            self = .zoom(try container.decode(ZoomEffectPayload.self, forKey: .payload))
        case .blur:
            self = .blur(try container.decode(BlurEffectPayload.self, forKey: .payload))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)

        switch self {
        case .zoom(let payload):
            try container.encode(payload, forKey: .payload)
        case .blur(let payload):
            try container.encode(payload, forKey: .payload)
        }
    }
}

public struct ZoomEffectPayload: Codable, Sendable, Equatable {
    public var zoomLevel: Double
    public var focusMode: ZoomFocusMode

    public init(zoomLevel: Double = 1.5, focusMode: ZoomFocusMode = .followCursor) {
        self.zoomLevel = zoomLevel
        self.focusMode = focusMode
    }
}

public struct NormalizedRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let centeredRedaction = NormalizedRect(x: 0.2, y: 0.35, width: 0.6, height: 0.3)

    public func clamped(minSize: Double = 0.04) -> NormalizedRect {
        let minimum = max(0, min(1, minSize))
        let clampedWidth = max(minimum, min(1, width))
        let clampedHeight = max(minimum, min(1, height))
        let clampedX = max(0, min(1 - clampedWidth, x))
        let clampedY = max(0, min(1 - clampedHeight, y))
        return NormalizedRect(
            x: clampedX,
            y: clampedY,
            width: clampedWidth,
            height: clampedHeight
        )
    }

    public func cgRect(in size: CGSize) -> CGRect {
        let rectWidth = max(0, min(1, width)) * size.width
        let rectHeight = max(0, min(1, height)) * size.height
        let originX = max(0, min(1, x)) * size.width
        let originYFromTop = max(0, min(1, y)) * size.height
        let originY = size.height - originYFromTop - rectHeight
        return CGRect(x: originX, y: originY, width: rectWidth, height: rectHeight)
    }
}

public struct BlurEffectPayload: Codable, Sendable, Equatable {
    public var rect: NormalizedRect
    public var radius: Double

    public init(rect: NormalizedRect = .centeredRedaction, radius: Double = 18) {
        self.rect = rect
        self.radius = radius
    }
}

public extension Array where Element == RecordingEffectSegment {
    var zoomSegments: [ZoomSegment] {
        compactMap(\.zoomSegment)
            .sorted { lhs, rhs in
                if lhs.startTime == rhs.startTime {
                    lhs.endTime < rhs.endTime
                } else {
                    lhs.startTime < rhs.startTime
                }
            }
    }

    mutating func replaceZoomSegments(with zoomSegments: [ZoomSegment]) {
        removeAll { $0.kind == .zoom }
        append(contentsOf: zoomSegments.map(RecordingEffectSegment.init(zoom:)))
        sort { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                lhs.endTime < rhs.endTime
            } else {
                lhs.startTime < rhs.startTime
            }
        }
    }
}
