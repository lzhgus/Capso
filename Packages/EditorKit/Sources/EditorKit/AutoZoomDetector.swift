// Packages/EditorKit/Sources/EditorKit/AutoZoomDetector.swift

import Foundation
import EffectsKit

/// Detects "interesting moments" in cursor telemetry and proposes zoom segments.
///
/// Three candidate streams are built:
///   1. Clicks (left / right) — a lone click produces a candidate at its
///      position; a burst of nearby clicks becomes one longer candidate, zoomed
///      further when the clicks come in quick succession.
///   2. Dwells — either dense sampled runs where the cursor is nearly stationary,
///      or sparse same-position gaps between interactions, produce a candidate.
///   3. Typing — a run of key presses produces a candidate where the cursor is.
///
/// Candidates are ranked by a "significance" strength (in ms-equivalent units),
/// then a greedy spacing filter drops any two candidates whose center times are
/// within `minSpacing`. Segments are built (with click pre-roll / dwell length
/// rules) and any overlapping segments are merged with a weighted focus.
public enum AutoZoomDetector {

    // MARK: - Tuning constants

    /// Minimum stillness required to count as a dwell.
    static let minDwellDuration: TimeInterval = 0.45
    /// Long stillness should qualify, but should not dominate ranking or segment length.
    static let maxDwellInfluenceDuration: TimeInterval = 2.60
    /// Cursor movement below this normalized distance counts as stationary.
    static let dwellMoveThreshold: Double = 0.02
    /// Dense runs only stay contiguous while the event stream itself is dense.
    static let maxDenseDwellGap: TimeInterval = 0.20
    /// Minimum gap between accepted candidates' center times. Must be at
    /// least the maximum segment length (≈3.6s: max(defaultDuration,
    /// maxDwellInfluenceDuration + 2*dwellBuffer) = max(3, 3.6) = 3.6)
    /// PLUS a small buffer — otherwise adjacent accepted candidates produce
    /// overlapping segments that all chain-merge into one giant zoom.
    static let minSpacing: TimeInterval = 4.00
    /// Merge two adjacent segments only when they almost touch. Keeping this
    /// small prevents the chain-merge pathology that turned 8 candidates into
    /// a single 22-second zoom.
    static let mergeGap: TimeInterval = 0.50
    /// Zoom-in starts this far before a click (so it settles on the click).
    static let clickPreRoll: TimeInterval = 1.0
    /// Time spent zoomed after a click (shows the result).
    static let clickPostRoll: TimeInterval = 2.0
    /// Padding each side of a dwell run when computing segment length.
    static let dwellBuffer: TimeInterval = 0.5
    static let defaultZoomLevel: Double = 1.5
    static let defaultDuration: TimeInterval = 3.0
    /// Clicks join a burst when each follows the previous within this time…
    static let clickBurstGap: TimeInterval = 3.0
    /// …and lands within this normalized distance of it.
    static let clickBurstRadius: Double = 0.25
    /// Follow-up clicks this quick count extra towards a burst's density.
    static let quickClickGap: TimeInterval = 0.5
    /// Bursts at least this dense zoom in further.
    static let denseBurstScore: Double = 3.0
    static let denseBurstZoomLevel: Double = 2.0
    static let maxSegmentDuration: TimeInterval = 60
    /// Telemetry can record the same click twice (event tap and event monitor).
    static let duplicateClickWindow: TimeInterval = 0.05
    /// Key presses closer together than this form one typing run…
    static let typingGap: TimeInterval = 0.5
    /// …of at least this many presses.
    static let minTypingKeys = 4
    static let typingPreRoll: TimeInterval = 0.3
    /// A click this soon before typing starts is taken as the click that focused the field.
    static let focusingClickWindow: TimeInterval = 2.0
    static let typingPostRoll: TimeInterval = 0.8
    // MARK: - Candidate model (internal)

    private enum CandidateKind {
        case click
        case clickBurst(first: TimeInterval, last: TimeInterval, zoomLevel: Double)
        case typing(first: TimeInterval, last: TimeInterval, preRoll: TimeInterval)
        case dwell(duration: TimeInterval)
    }

    private struct Candidate {
        let kind: CandidateKind
        let centerTime: TimeInterval
        let focus: (x: Double, y: Double)
        /// Ranking strength in ms-equivalent units. Clicks = 1000 (bursts and
        /// typing rank higher), dwells use a capped duration so long pauses
        /// still qualify without dominating.
        let strength: Double
    }

    // MARK: - Public entry

    public static func detect(
        events: [CursorEvent],
        duration: TimeInterval
    ) -> [ZoomSegment] {
        guard duration > 0 else { return [] }

        // Step A: build candidates
        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        let clickCandidates = buildClickCandidates(from: sortedEvents)
        let dwellCandidates = buildDwellCandidates(from: sortedEvents.filter { $0.type != .keyDown })
        let typingCandidates = buildTypingCandidates(from: sortedEvents)
        let (typing, remainingClicks) = attachFocusingClicks(typing: typingCandidates, clicks: clickCandidates)
        let all = remainingClicks + dwellCandidates + typing

        // Step B: rank and filter by spacing
        let accepted = filterBySpacing(candidates: all, videoDuration: duration)

        // Step C: build segments
        let segments = accepted.map { makeSegment(from: $0, videoDuration: duration) }
            .compactMap { $0 }
            .sorted { $0.startTime < $1.startTime }

        // Step D: merge overlaps
        return mergeOverlapping(segments: segments)
    }

    // MARK: - Step A: candidates

    private static func buildClickCandidates(from events: [CursorEvent]) -> [Candidate] {
        let clicks = events.filter { $0.type == .leftClick || $0.type == .rightClick }
        var bursts: [[CursorEvent]] = []
        for click in clicks {
            if let last = bursts.last?.last, click.timestamp - last.timestamp < duplicateClickWindow {
                continue
            }
            if let last = bursts.last?.last,
               click.timestamp - last.timestamp <= clickBurstGap,
               hypot(click.x - last.x, click.y - last.y) <= clickBurstRadius {
                bursts[bursts.count - 1].append(click)
            } else {
                bursts.append([click])
            }
        }

        return bursts.map { burst in
            let first = burst[0]
            guard burst.count > 1, let last = burst.last else {
                return Candidate(kind: .click, centerTime: first.timestamp, focus: (first.x, first.y), strength: 1000.0)
            }
            let score = zip(burst, burst.dropFirst()).reduce(0.0) { score, pair in
                score + 1 + (pair.1.timestamp - pair.0.timestamp <= quickClickGap ? 1.5 : 0)
            }
            let count = Double(burst.count)
            return Candidate(
                kind: .clickBurst(
                    first: first.timestamp,
                    last: last.timestamp,
                    zoomLevel: score >= denseBurstScore ? denseBurstZoomLevel : defaultZoomLevel
                ),
                centerTime: (first.timestamp + last.timestamp) / 2,
                focus: (burst.map(\.x).reduce(0, +) / count, burst.map(\.y).reduce(0, +) / count),
                strength: 1000.0 * (1 + score)
            )
        }
    }

    /// Folds the click that focused a field into the typing run that follows it,
    /// so the zoom starts at the click and looks at the field.
    private static func attachFocusingClicks(
        typing: [Candidate],
        clicks: [Candidate]
    ) -> (typing: [Candidate], clicks: [Candidate]) {
        var remaining = clicks
        let attached = typing.map { run -> Candidate in
            guard case .typing(let first, let last, _) = run.kind else { return run }
            let lastClickTime: (Candidate) -> TimeInterval = { candidate in
                if case .clickBurst(_, let last, _) = candidate.kind { return last }
                return candidate.centerTime
            }
            guard let index = remaining.lastIndex(where: {
                let t = lastClickTime($0)
                return t <= first && first - t <= focusingClickWindow
            }) else { return run }
            let click = remaining.remove(at: index)
            let clickStart: TimeInterval
            if case .clickBurst(let burstFirst, _, _) = click.kind { clickStart = burstFirst } else { clickStart = click.centerTime }
            return Candidate(
                kind: .typing(first: clickStart, last: last, preRoll: clickPreRoll),
                centerTime: (clickStart + last) / 2,
                focus: click.focus,
                strength: max(run.strength, click.strength)
            )
        }
        return (attached, remaining)
    }

    private static func buildTypingCandidates(from events: [CursorEvent]) -> [Candidate] {
        let keys = events.filter { $0.type == .keyDown }
        var runs: [[CursorEvent]] = []
        for key in keys {
            if let last = runs.last?.last, key.timestamp - last.timestamp <= typingGap {
                runs[runs.count - 1].append(key)
            } else {
                runs.append([key])
            }
        }
        return runs.filter { $0.count >= minTypingKeys }.map { run in
            let count = Double(run.count)
            return Candidate(
                kind: .typing(first: run[0].timestamp, last: run[run.count - 1].timestamp, preRoll: typingPreRoll),
                centerTime: (run[0].timestamp + run[run.count - 1].timestamp) / 2,
                focus: (run.map(\.x).reduce(0, +) / count, run.map(\.y).reduce(0, +) / count),
                strength: 1000.0 + 100.0 * count
            )
        }
    }

    private static func buildDwellCandidates(from events: [CursorEvent]) -> [Candidate] {
        guard events.count > 1 else { return [] }
        return buildDenseDwellCandidates(from: events) + buildSparseDwellCandidates(from: events)
    }

    private static func buildDenseDwellCandidates(from events: [CursorEvent]) -> [Candidate] {
        var out: [Candidate] = []
        var runStart = 0

        for i in 1..<events.count {
            let gap = events[i].timestamp - events[i - 1].timestamp
            if !isStationary(events[i - 1], events[i]) || gap > maxDenseDwellGap {
                if let candidate = candidateFromDenseRun(events: events, startIdx: runStart, endIdx: i - 1) {
                    out.append(candidate)
                }
                runStart = i
            }
        }

        if let candidate = candidateFromDenseRun(events: events, startIdx: runStart, endIdx: events.count - 1) {
            out.append(candidate)
        }

        return out
    }

    private static func buildSparseDwellCandidates(from events: [CursorEvent]) -> [Candidate] {
        var out: [Candidate] = []

        for i in 1..<events.count {
            let previous = events[i - 1]
            let current = events[i]
            let gap = current.timestamp - previous.timestamp

            guard isStationary(previous, current), gap >= minDwellDuration else {
                continue
            }
            guard previous.type == .move || current.type == .move else {
                continue
            }

            let effectiveDuration = min(gap, maxDwellInfluenceDuration)
            out.append(
                Candidate(
                    kind: .dwell(duration: effectiveDuration),
                    centerTime: (previous.timestamp + current.timestamp) / 2.0,
                    focus: ((previous.x + current.x) / 2.0, (previous.y + current.y) / 2.0),
                    strength: effectiveDuration * 1000.0
                )
            )
        }

        return out
    }

    private static func candidateFromDenseRun(
        events: [CursorEvent],
        startIdx: Int,
        endIdx: Int
    ) -> Candidate? {
        guard startIdx < endIdx else { return nil }

        let runStart = events[startIdx].timestamp
        let runEnd = events[endIdx].timestamp
        let runDuration = runEnd - runStart
        guard runDuration >= minDwellDuration else { return nil }

        let effectiveDuration = min(runDuration, maxDwellInfluenceDuration)

        var sumX = 0.0
        var sumY = 0.0
        for idx in startIdx...endIdx {
            sumX += events[idx].x
            sumY += events[idx].y
        }

        let count = Double(endIdx - startIdx + 1)
        return Candidate(
            kind: .dwell(duration: effectiveDuration),
            centerTime: (runStart + runEnd) / 2.0,
            focus: (sumX / count, sumY / count),
            strength: effectiveDuration * 1000.0
        )
    }

    private static func isStationary(_ lhs: CursorEvent, _ rhs: CursorEvent) -> Bool {
        let dx = rhs.x - lhs.x
        let dy = rhs.y - lhs.y
        return (dx * dx + dy * dy).squareRoot() < dwellMoveThreshold
    }

    // MARK: - Step B: spacing filter

    private static func filterBySpacing(candidates: [Candidate], videoDuration: TimeInterval) -> [Candidate] {
        // Sort by strength descending; ties broken by earlier centerTime.
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.strength != rhs.strength { return lhs.strength > rhs.strength }
            return lhs.centerTime < rhs.centerTime
        }

        // Bursts and typing runs can be long, so also keep their segments apart.
        func span(_ c: Candidate) -> (start: TimeInterval, end: TimeInterval) {
            guard let segment = makeSegment(from: c, videoDuration: videoDuration) else { return (c.centerTime, c.centerTime) }
            return (segment.startTime, segment.endTime)
        }
        var accepted: [Candidate] = []
        for candidate in sorted {
            let candidateSpan = span(candidate)
            let conflicts = accepted.contains { other in
                let otherSpan = span(other)
                return abs(candidate.centerTime - other.centerTime) < minSpacing
                    || (candidateSpan.start < otherSpan.end + mergeGap && otherSpan.start < candidateSpan.end + mergeGap)
            }
            if !conflicts {
                accepted.append(candidate)
            }
        }
        return accepted
    }

    // MARK: - Step C: segment construction

    private static func makeSegment(
        from candidate: Candidate,
        videoDuration: TimeInterval
    ) -> ZoomSegment? {
        let (rawStart, rawEnd): (TimeInterval, TimeInterval)
        var zoomLevel = defaultZoomLevel
        switch candidate.kind {
        case .click:
            rawStart = candidate.centerTime - clickPreRoll
            rawEnd = candidate.centerTime + clickPostRoll
        case .clickBurst(let first, let last, let level):
            rawStart = first - clickPreRoll
            rawEnd = min(last + clickPostRoll, rawStart + maxSegmentDuration)
            zoomLevel = level
        case .typing(let first, let last, let preRoll):
            rawStart = first - preRoll
            rawEnd = min(last + typingPostRoll, rawStart + maxSegmentDuration)
        case .dwell(let dwellDuration):
            let desired = max(defaultDuration, dwellDuration + 2 * dwellBuffer)
            let half = desired / 2.0
            rawStart = candidate.centerTime - half
            rawEnd = candidate.centerTime + half
        }

        // Shift (don't squish) to stay within [0, videoDuration].
        let segDuration = rawEnd - rawStart
        var start = rawStart
        var end = rawEnd
        if start < 0 {
            start = 0
            end = min(videoDuration, segDuration)
        } else if end > videoDuration {
            end = videoDuration
            start = max(0, end - segDuration)
        }

        guard end > start else { return nil }

        return ZoomSegment(
            startTime: start,
            endTime: end,
            zoomLevel: zoomLevel,
            focusMode: .manual(x: candidate.focus.x, y: candidate.focus.y),
            source: .auto
        )
    }

    // MARK: - Step D: merge overlapping

    /// Merge segments whose gap is within `mergeGap` into a single segment whose
    /// focus is a duration-weighted average. Runs pair-wise in time order, so
    /// a chain A+B+C merges as (A+B) then +C — not a three-way centroid.
    private static func mergeOverlapping(segments: [ZoomSegment]) -> [ZoomSegment] {
        guard !segments.isEmpty else { return [] }
        var merged: [ZoomSegment] = [segments[0]]

        for next in segments.dropFirst() {
            let prev = merged[merged.count - 1]
            if next.startTime <= prev.endTime + mergeGap {
                // Weighted focus by each segment's own duration
                let prevDur = prev.duration
                let nextDur = next.duration
                let total = prevDur + nextDur
                let (px, py) = focusComponents(prev.focusMode)
                let (nx, ny) = focusComponents(next.focusMode)
                let mx = (px * prevDur + nx * nextDur) / total
                let my = (py * prevDur + ny * nextDur) / total

                merged[merged.count - 1] = ZoomSegment(
                    id: prev.id,
                    startTime: prev.startTime,
                    endTime: max(prev.endTime, next.endTime),
                    zoomLevel: max(prev.zoomLevel, next.zoomLevel),
                    focusMode: .manual(x: mx, y: my),
                    source: .auto
                )
            } else {
                merged.append(next)
            }
        }
        return merged
    }

    private static func focusComponents(_ mode: ZoomFocusMode) -> (Double, Double) {
        if case .manual(let x, let y) = mode { return (x, y) }
        // All auto segments are built with .manual focus mode, so this branch
        // is unreachable. Fall back to frame center if somehow encountered.
        return (0.5, 0.5)
    }
}
