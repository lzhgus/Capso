import SwiftUI
import EditorKit

struct ZoomTrackView: View {
    @Bindable var coordinator: EditorCoordinator

    var body: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.03))

                Text("Zoom")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.quaternary)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)

                ForEach(Array(coordinator.project.zoomSegments.enumerated()), id: \.element.id) { index, segment in
                    zoomSegmentView(segment, trackWidth: trackWidth)
                        .transition(
                            .opacity.animation(
                                .easeOut(duration: 0.2).delay(Double(index) * 0.03)
                            )
                        )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { location in
                let time = xToTime(location.x, in: trackWidth)
                coordinator.addZoomSegment(at: time)
            }
            .onTapGesture(count: 1) { _ in
                coordinator.selectedZoomSegmentID = nil
            }
        }
        .animation(.default, value: coordinator.project.zoomSegments.map(\.id))
        .frame(height: 28)
    }

    private func zoomSegmentView(_ segment: ZoomSegment, trackWidth: Double) -> some View {
        let startX = timeToX(segment.startTime, in: trackWidth)
        let endX = timeToX(segment.endTime, in: trackWidth)
        let width = max(20, endX - startX)
        let isSelected = coordinator.selectedZoomSegmentID == segment.id

        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.purple.opacity(isSelected ? 0.5 : 0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            isSelected ? Color.purple : Color.purple.opacity(0.5),
                            lineWidth: isSelected ? 1.5 : 0.5
                        )
                )

            HStack(spacing: 2) {
                Image(systemName: segment.source == .auto ? "wand.and.stars" : "magnifyingglass")
                    .font(.system(size: 8))
                Text(String(format: "%.1fx", segment.zoomLevel))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(.white.opacity(0.8))
            .allowsHitTesting(false)

            HStack {
                resizeHandle(segment: segment, edge: .leading, trackWidth: trackWidth)
                Spacer()
                resizeHandle(segment: segment, edge: .trailing, trackWidth: trackWidth)
            }
        }
        .frame(width: width, height: 24)
        .offset(x: startX)
        .highPriorityGesture(dragToMoveGesture(segment: segment, trackWidth: trackWidth))
        .onTapGesture {
            coordinator.selectedZoomSegmentID = segment.id
        }
        .contextMenu {
            Button("Delete") { coordinator.removeZoomSegment(id: segment.id) }
            Divider()
            Menu("Zoom Level") {
                ForEach([1.25, 1.5, 1.8, 2.0, 2.5, 3.0], id: \.self) { level in
                    Button(String(format: "%.1fx", level)) {
                        coordinator.setZoomLevel(id: segment.id, level: level)
                    }
                }
            }
            Menu("Focus") {
                Button("Follow Cursor") { coordinator.setZoomFocusMode(id: segment.id, mode: .followCursor) }
                Button("Center") { coordinator.setZoomFocusMode(id: segment.id, mode: .manual(x: 0.5, y: 0.5)) }
            }
        }
    }

    private func resizeHandle(segment: ZoomSegment, edge: HorizontalEdge, trackWidth: Double) -> some View {
        Color.clear
            .frame(width: 8, height: 24)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let baseX = timeToX(segment.startTime, in: trackWidth)
                        let time = xToTime(value.location.x + baseX, in: trackWidth)
                        let clamped = max(0, min(coordinator.duration, time))
                        if edge == .leading {
                            coordinator.resizeZoomSegment(id: segment.id, newStart: clamped)
                        } else {
                            coordinator.resizeZoomSegment(id: segment.id, newEnd: clamped)
                        }
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }

    private func dragToMoveGesture(segment: ZoomSegment, trackWidth: Double) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                coordinator.selectedZoomSegmentID = segment.id
                let dragTime = xToTime(value.location.x, in: trackWidth)
                coordinator.moveZoomSegment(id: segment.id, to: dragTime - segment.duration / 2)
            }
    }

    private func timeToX(_ time: TimeInterval, in width: Double) -> Double {
        guard coordinator.duration > 0 else { return 0 }
        return (time / coordinator.duration) * width
    }

    private func xToTime(_ x: Double, in width: Double) -> TimeInterval {
        guard width > 0 else { return 0 }
        return (x / width) * coordinator.duration
    }
}
