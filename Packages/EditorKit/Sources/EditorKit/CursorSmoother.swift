// Packages/EditorKit/Sources/EditorKit/CursorSmoother.swift

import Foundation
import EffectsKit

// MARK: - SmoothedCursorTimeline

/// A precomputed timeline of spring-smoothed cursor positions sampled at regular intervals.
///
/// Positions can be queried at arbitrary times via linear interpolation between adjacent samples.
public struct SmoothedCursorTimeline: Sendable {

    // MARK: - Internal storage

    let xs: [Double]
    let ys: [Double]

    // MARK: - Public properties

    /// The time interval between consecutive samples (1 / fps).
    public let sampleInterval: TimeInterval

    /// Total duration covered by this timeline in seconds.
    public let duration: TimeInterval

    /// Total number of precomputed samples.
    public var sampleCount: Int { xs.count }

    // MARK: - Init

    init(xs: [Double], ys: [Double], sampleInterval: TimeInterval, duration: TimeInterval) {
        self.xs = xs
        self.ys = ys
        self.sampleInterval = sampleInterval
        self.duration = duration
    }

    // MARK: - Interpolated lookup

    /// Returns the smoothed cursor position at an arbitrary time via linear interpolation.
    ///
    /// Time is clamped to `[0, duration]` before lookup.
    public func position(at time: TimeInterval) -> (x: Double, y: Double) {
        guard sampleCount > 0 else { return (0, 0) }
        if sampleCount == 1 { return (xs[0], ys[0]) }

        let clampedTime = min(max(time, 0), duration)
        let exactIndex  = clampedTime / sampleInterval
        let lower       = Int(exactIndex)

        // If exactly on the last sample (or beyond), return it directly.
        guard lower < sampleCount - 1 else {
            return (xs[sampleCount - 1], ys[sampleCount - 1])
        }

        let fraction = exactIndex - Double(lower)
        let x = xs[lower] + fraction * (xs[lower + 1] - xs[lower])
        let y = ys[lower] + fraction * (ys[lower + 1] - ys[lower])
        return (x, y)
    }
}

// MARK: - CursorSmoother

/// Applies spring-physics smoothing to raw cursor telemetry data.
///
/// Given a `CursorTelemetryData` instance (produced by `CursorTelemetry` during recording),
/// `CursorSmoother` can:
/// - Look up raw (unsmoothed) cursor positions at arbitrary times via binary search + lerp.
/// - Build a `SmoothedCursorTimeline` whose positions lag the raw cursor in a physically
///   plausible way — using `Spring2D` for independent X/Y spring simulation.
public final class CursorSmoother: Sendable {

    // MARK: - Stored properties

    private static let maxInterpolationGap: TimeInterval = 0.12

    private let telemetry: CursorTelemetryData
    private let config: CursorSmoothingConfig

    // MARK: - Init

    public init(telemetry: CursorTelemetryData, config: CursorSmoothingConfig) {
        self.telemetry = telemetry
        self.config    = config
    }

    // MARK: - Raw position

    /// Returns the raw (unsmoothed) cursor position at `time`.
    ///
    /// - If `time` is before the first event, the first event's position is returned.
    /// - If `time` is after the last event, the last event's position is returned.
    /// - Short gaps are linearly interpolated to keep genuine motion smooth.
    /// - Long gaps are treated as stillness, so the previous position is held until
    ///   the next real event instead of inventing phantom cursor travel.
    public func rawPosition(at time: TimeInterval) -> (x: Double, y: Double) {
        let events = telemetry.events

        guard !events.isEmpty else { return (0, 0) }
        if events.count == 1 { return (events[0].x, events[0].y) }

        // Clamp before first event.
        if time <= events[0].timestamp {
            return (events[0].x, events[0].y)
        }

        // Clamp after last event.
        let last = events[events.count - 1]
        if time >= last.timestamp {
            return (last.x, last.y)
        }

        // Binary search for the last event with timestamp ≤ time.
        var lo = 0
        var hi = events.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if events[mid].timestamp <= time {
                lo = mid
            } else {
                hi = mid
            }
        }

        let before = events[lo]
        let after  = events[hi]
        let span   = after.timestamp - before.timestamp

        // Avoid division by zero (duplicate timestamps).
        guard span > 0 else { return (before.x, before.y) }
        guard span <= Self.maxInterpolationGap else { return (before.x, before.y) }

        let t = (time - before.timestamp) / span
        return (
            before.x + t * (after.x - before.x),
            before.y + t * (after.y - before.y)
        )
    }

    // MARK: - Click events

    /// Returns all click events (`.leftClick` or `.rightClick`) from the telemetry data.
    public func clickEvents() -> [CursorEvent] {
        telemetry.events.filter { $0.type == .leftClick || $0.type == .rightClick }
    }

    // MARK: - Smoothed timeline

    /// Precomputes a `SmoothedCursorTimeline` by stepping through the recording at `1/fps`
    /// intervals and feeding the raw position as the target into a `Spring2D` simulator.
    ///
    /// When `config.enabled == false`, the raw positions are stored directly (no lag).
    ///
    /// - Parameters:
    ///   - fps: Sample rate for the output timeline (e.g. 60).
    ///   - duration: Total duration of the recording in seconds.
    /// - Returns: A `SmoothedCursorTimeline` ready for real-time or export playback.
    public func buildSmoothedTimeline(fps: Double, duration: TimeInterval) -> SmoothedCursorTimeline {
        let dt = 1.0 / fps
        // Inclusive endpoint: 0, dt, 2*dt, …, duration  →  floor(duration/dt)+1 samples
        let count = Int((duration / dt).rounded(.down)) + 1

        var xs = [Double](repeating: 0, count: count)
        var ys = [Double](repeating: 0, count: count)

        if config.enabled {
            var spring = Spring2D(
                stiffness: config.stiffness,
                damping:   config.damping,
                mass:      config.mass
            )

            // Seed the spring at the first raw position so we don't start from (0,0).
            let seed = rawPosition(at: 0)
            spring.reset(x: seed.x, y: seed.y)

            for i in 0..<count {
                let t = Double(i) * dt
                let raw = rawPosition(at: t)
                let pos = spring.step(towardX: raw.x, y: raw.y, deltaTime: dt)
                xs[i] = pos.x
                ys[i] = pos.y
            }
        } else {
            // Smoothing disabled: copy raw positions verbatim.
            for i in 0..<count {
                let t = Double(i) * dt
                let raw = rawPosition(at: t)
                xs[i] = raw.x
                ys[i] = raw.y
            }
        }

        return SmoothedCursorTimeline(
            xs: xs,
            ys: ys,
            sampleInterval: dt,
            duration: duration
        )
    }
}
