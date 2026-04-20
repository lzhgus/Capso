import Foundation
import EffectsKit

public final class CursorOverlayProvider: Sendable {
    private static let clickDuration: TimeInterval = 0.13
    private static let clickMinScale: Double = 0.8

    private let clicks: [CursorEvent]

    public init(clickEvents: [CursorEvent]) {
        self.clicks = clickEvents
            .filter { $0.type == .leftClick || $0.type == .rightClick }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func clickScale(at time: TimeInterval) -> Double {
        for click in clicks.reversed() {
            let elapsed = time - click.timestamp
            if elapsed < 0 { continue }
            if elapsed > Self.clickDuration { break }
            let progress = elapsed / Self.clickDuration
            return Self.clickMinScale + (1.0 - Self.clickMinScale) * smoothstep(progress)
        }
        return 1.0
    }

    private func smoothstep(_ t: Double) -> Double {
        let c = max(0, min(1, t))
        return c * c * (3 - 2 * c)
    }
}
