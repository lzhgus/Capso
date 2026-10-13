import CoreImage
import Foundation
import EffectsKit

public final class CursorOverlayProvider: Sendable {
    private static let clickDuration: TimeInterval = 0.13
    private static let clickMinScale: Double = 0.8

    /// Only pauses at least this long hide the cursor.
    static let idleThreshold: TimeInterval = 1.5
    /// The cursor starts fading this long after it last moved…
    static let idleFadeDelay: TimeInterval = 0.1
    /// …and fades out (and back in before it moves again) over this long.
    static let idleFadeDuration: TimeInterval = 0.3

    /// Click ripple: grows in while the button goes down, holds while it's
    /// held, then widens and fades after release.
    static let ripplePressDuration: TimeInterval = 0.2
    static let rippleReleaseDuration: TimeInterval = 0.2
    /// Used when a recording has no release events (older telemetry).
    static let assumedPressLength: TimeInterval = 0.1

    private let clicks: [CursorEvent]
    /// Release time for each click, aligned with `clicks`.
    private let releases: [TimeInterval]
    /// Pauses in pointer activity long enough to hide the cursor, as (last activity, next activity).
    private let idleGaps: [(start: TimeInterval, end: TimeInterval)]

    /// - Parameter hidesIdleCursor: Fade the cursor out while the mouse is still
    ///   (including while typing) and back in just before it moves again.
    public init(events: [CursorEvent], hidesIdleCursor: Bool = false) {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        let clicks = sorted.filter { $0.type == .leftClick || $0.type == .rightClick }
        let ups = sorted.filter { $0.type == .mouseUp }.map(\.timestamp)
        self.clicks = clicks
        self.releases = clicks.enumerated().map { index, click in
            let nextClick = index + 1 < clicks.count ? clicks[index + 1].timestamp : .infinity
            return ups.first { $0 >= click.timestamp && $0 < nextClick } ?? click.timestamp + Self.assumedPressLength
        }

        guard hidesIdleCursor else {
            self.idleGaps = []
            return
        }
        // The start of the recording counts as activity, so a cursor that never
        // moves (or only types) fades like any other pause.
        let activity = [0] + sorted.filter { $0.type != .keyDown && $0.timestamp > 0 }.map(\.timestamp)
        var gaps = zip(activity, activity.dropFirst())
            .filter { $1 - $0 >= Self.idleThreshold }
            .map { (start: $0, end: $1) }
        if let last = activity.last {
            gaps.append((start: last, end: .infinity))
        }
        self.idleGaps = gaps
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

    /// The ripple at `time` as a radius (fraction of the full radius) and opacity, or `nil`.
    public func ripple(at time: TimeInterval) -> (radius: Double, opacity: Double)? {
        guard let index = clicks.lastIndex(where: { $0.timestamp <= time }) else { return nil }
        let down = clicks[index].timestamp
        let pressed = down + Self.ripplePressDuration
        let released = max(releases[index], pressed)
        if time < pressed {
            return (0.6 + 0.4 * smoothstep((time - down) / Self.ripplePressDuration), 1)
        }
        if time < released { return (1, 1) }
        let fade = (time - released) / Self.rippleReleaseDuration
        guard fade < 1 else { return nil }
        return (1 + 0.5 * smoothstep(fade), 1 - smoothstep(fade))
    }

    /// A soft disc for the ripple, centred on the origin, or `nil` when there is none.
    /// - Parameter fullRadius: Radius in source pixels at the ripple's full size.
    public func rippleImage(at time: TimeInterval, fullRadius: CGFloat) -> CIImage? {
        guard let ripple = ripple(at: time) else { return nil }
        let radius = fullRadius * CGFloat(ripple.radius)
        let alpha = 0.35 * CGFloat(ripple.opacity)
        let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: 0, y: 0),
            "inputRadius0": radius * 0.82,
            "inputRadius1": radius,
            "inputColor0": CIColor(red: 0.25, green: 0.55, blue: 1, alpha: alpha),
            "inputColor1": CIColor(red: 0.25, green: 0.55, blue: 1, alpha: 0),
        ])
        return gradient?.outputImage?.cropped(to: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
    }

    /// 1 when the cursor is fully shown, 0 when hidden.
    public func opacity(at time: TimeInterval) -> Double {
        guard let gap = idleGaps.first(where: { $0.start <= time && time < $0.end }) else { return 1 }
        let fadeOutStart = gap.start + Self.idleFadeDelay
        let fadeOut = (time - fadeOutStart) / Self.idleFadeDuration
        let fadeIn = (gap.end - time) / Self.idleFadeDuration
        return 1 - smoothstep(min(fadeOut, fadeIn))
    }

    /// The cursor image as it should be drawn at `time` (click squeeze and idle fade
    /// applied), or `nil` when it is fully hidden.
    public func styledCursor(_ cursor: CIImage, at time: TimeInterval) -> CIImage? {
        let alpha = CGFloat(opacity(at: time))
        guard alpha > 0 else { return nil }
        let scale = CGFloat(clickScale(at: time))
        var image = scale < 1 ? cursor.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) : cursor
        if alpha < 1 {
            let vector = { (i: Int) in CIVector(values: (0..<4).map { $0 == i ? alpha : 0 }, count: 4) }
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": vector(0), "inputGVector": vector(1),
                "inputBVector": vector(2), "inputAVector": vector(3),
            ])
        }
        return image
    }

    private func smoothstep(_ t: Double) -> Double {
        let c = max(0, min(1, t))
        return c * c * (3 - 2 * c)
    }
}
