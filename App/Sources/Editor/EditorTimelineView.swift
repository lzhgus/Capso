import SwiftUI
import EditorKit

struct EditorTimelineView: View {
    @Bindable var coordinator: EditorCoordinator
    @State private var isScrubbingTimeline = false
    @State private var shouldResumePlaybackAfterScrub = false

    var body: some View {
        VStack(spacing: 6) {
            trimRegionRow

            GeometryReader { geo in
                let trackWidth = geo.size.width
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))

                    // Trim regions (shaded)
                    ForEach(coordinator.project.trimRegions) { trim in
                        let startX = timeToX(trim.startTime, in: trackWidth)
                        let endX = timeToX(trim.endTime, in: trackWidth)
                        Rectangle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: max(1, endX - startX))
                            .offset(x: startX)
                    }

                    // Head trim handle
                    trimHandle(
                        time: coordinator.effectiveStartTime,
                        trackWidth: trackWidth,
                        edge: .leading
                    ) { newTime in
                        coordinator.setHeadTrim(to: newTime)
                    }

                    // Tail trim handle
                    trimHandle(
                        time: coordinator.effectiveEndTime,
                        trackWidth: trackWidth,
                        edge: .trailing
                    ) { newTime in
                        coordinator.setTailTrim(to: newTime)
                    }

                    // Playhead
                    playhead(trackWidth: trackWidth)
                }
                .contentShape(Rectangle())
                .gesture(trackScrubGesture(trackWidth: trackWidth))
            }
            .frame(height: 40)

            ZoomTrackView(coordinator: coordinator)

            timeMarkers
        }
    }

    // MARK: - Playhead

    private func playhead(trackWidth: Double) -> some View {
        let x = timeToX(coordinator.currentTime, in: trackWidth)
        return ZStack {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: 48)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 10, height: 10)
                .offset(y: -24)
        }
        .offset(x: x - 1)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    beginScrubbing()
                    scrub(to: value.location.x, trackWidth: trackWidth)
                }
                .onEnded { _ in
                    endScrubbing()
                }
        )
    }

    private func trackScrubGesture(trackWidth: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                beginScrubbing()
                scrub(to: value.location.x, trackWidth: trackWidth)
            }
            .onEnded { _ in
                endScrubbing()
            }
    }

    // MARK: - Trim Handles

    private func trimHandle(
        time: TimeInterval,
        trackWidth: Double,
        edge: HorizontalEdge,
        onDrag: @escaping (TimeInterval) -> Void
    ) -> some View {
        let x = timeToX(time, in: trackWidth)
        // Visible handle: 12pt wide so it's easier to see
        let handleWidth: Double = 12
        // Invisible hit area: 28pt wide so small touches at the edge register
        let hitAreaWidth: Double = 28

        // Keep the visible bar inset from the edge so it's never clipped:
        // leading handle sits to the RIGHT of x, trailing sits to the LEFT.
        // This ensures both handles are always within the track bounds.
        let visibleOffset = edge == .leading
            ? max(0, x)                           // never goes negative
            : min(trackWidth - handleWidth, x - handleWidth)

        // The hit area is centered on the visible bar
        let hitOffset = visibleOffset - (hitAreaWidth - handleWidth) / 2

        return ZStack {
            // Invisible oversized tap/drag region gives a larger click target
            Color.clear
                .frame(width: hitAreaWidth, height: 44)

            // Visible orange bar
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.orange.opacity(0.85))
                .frame(width: handleWidth, height: 44)
        }
        .offset(x: hitOffset)
        // highPriorityGesture ensures the handle drag takes precedence over
        // the parent ZStack's onTapGesture (seek) handler.
        .highPriorityGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    // value.location is in the ZStack coordinate space (0…trackWidth),
                    // so we can convert directly to time with xToTime.
                    let newTime = xToTime(value.location.x, in: trackWidth)
                    let clamped = max(0, min(coordinator.duration, newTime))
                    onDrag(clamped)
                }
        )
        .help(edge == .leading ? "Drag to trim start" : "Drag to trim end")
    }

    // MARK: - Trim Region Row

    private var trimRegionRow: some View {
        HStack {
            let segmentTrims = coordinator.project.trimRegions.filter {
                $0.startTime > 0.01 && $0.endTime < coordinator.duration - 0.01
            }
            if !segmentTrims.isEmpty {
                Text("\(segmentTrims.count) trimmed segment\(segmentTrims.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if coordinator.project.effectiveDuration < coordinator.duration {
                Text("Duration: \(coordinator.formatTime(coordinator.project.effectiveDuration))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Time Markers

    private var timeMarkers: some View {
        HStack {
            Text(coordinator.formatTime(0))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
            Spacer()
            Text(coordinator.formatTime(coordinator.duration / 2))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
            Spacer()
            Text(coordinator.formatTime(coordinator.duration))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
    }

    // MARK: - Coordinate Conversion

    private func timeToX(_ time: TimeInterval, in width: Double) -> Double {
        guard coordinator.duration > 0 else { return 0 }
        return (time / coordinator.duration) * width
    }

    private func xToTime(_ x: Double, in width: Double) -> TimeInterval {
        guard width > 0 else { return 0 }
        return (x / width) * coordinator.duration
    }

    private func beginScrubbing() {
        guard !isScrubbingTimeline else { return }
        isScrubbingTimeline = true
        shouldResumePlaybackAfterScrub = coordinator.isPlaying
        if coordinator.isPlaying {
            coordinator.pause()
        }
    }

    private func scrub(to x: Double, trackWidth: Double) {
        let clampedX = max(0, min(trackWidth, x))
        let time = xToTime(clampedX, in: trackWidth)
        coordinator.seek(to: time)
    }

    private func endScrubbing() {
        guard isScrubbingTimeline else { return }
        isScrubbingTimeline = false
        if shouldResumePlaybackAfterScrub {
            coordinator.play()
        }
        shouldResumePlaybackAfterScrub = false
    }
}
