import SwiftUI
import EditorKit

struct BlurRegionOverlay: View {
    @Bindable var coordinator: EditorCoordinator
    @State private var activeGestureRect: NormalizedRect?

    private let handleSize: Double = 12
    private let minSide: Double = 0.04

    var body: some View {
        GeometryReader { proxy in
            if let segment = coordinator.selectedEffectSegment,
               case .blur(let payload) = segment.payload {
                let rect = payload.rect.clamped(minSize: minSide)
                let frame = rectFrame(rect, in: proxy.size)

                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(moveGesture(segmentID: segment.id, rect: rect, size: proxy.size))

                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.08))
                        )
                        .allowsHitTesting(false)

                    resizeHandle(.topLeading, segmentID: segment.id, rect: rect, size: proxy.size)
                    resizeHandle(.topTrailing, segmentID: segment.id, rect: rect, size: proxy.size)
                    resizeHandle(.bottomLeading, segmentID: segment.id, rect: rect, size: proxy.size)
                    resizeHandle(.bottomTrailing, segmentID: segment.id, rect: rect, size: proxy.size)
                }
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
            }
        }
        .allowsHitTesting(coordinator.selectedEffectSegment?.kind == .blur)
    }

    private func rectFrame(_ rect: NormalizedRect, in size: CGSize) -> CGRect {
        CGRect(
            x: rect.x * size.width,
            y: rect.y * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }

    private func moveGesture(
        segmentID: UUID,
        rect: NormalizedRect,
        size: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                let startRect = activeGestureRect ?? rect
                activeGestureRect = startRect
                let next = NormalizedRect(
                    x: startRect.x + value.translation.width / size.width,
                    y: startRect.y + value.translation.height / size.height,
                    width: startRect.width,
                    height: startRect.height
                )
                coordinator.setBlurRect(id: segmentID, rect: next)
            }
            .onEnded { _ in
                activeGestureRect = nil
            }
    }

    private enum ResizeCorner {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing
    }

    private func resizeHandle(
        _ corner: ResizeCorner,
        segmentID: UUID,
        rect: NormalizedRect,
        size: CGSize
    ) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
            .position(position(for: corner, rect: rect, size: size))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard size.width > 0, size.height > 0 else { return }
                        let startRect = activeGestureRect ?? rect
                        activeGestureRect = startRect
                        let next = resizedRect(
                            startRect,
                            corner: corner,
                            translation: CGSize(
                                width: value.translation.width / size.width,
                                height: value.translation.height / size.height
                            )
                        )
                        coordinator.setBlurRect(id: segmentID, rect: next)
                    }
                    .onEnded { _ in
                        activeGestureRect = nil
                    }
            )
    }

    private func position(for corner: ResizeCorner, rect: NormalizedRect, size: CGSize) -> CGPoint {
        let x: Double
        let y: Double

        switch corner {
        case .topLeading, .bottomLeading:
            x = 0
        case .topTrailing, .bottomTrailing:
            x = rect.width * size.width
        }

        switch corner {
        case .topLeading, .topTrailing:
            y = 0
        case .bottomLeading, .bottomTrailing:
            y = rect.height * size.height
        }

        return CGPoint(x: x, y: y)
    }

    private func resizedRect(
        _ rect: NormalizedRect,
        corner: ResizeCorner,
        translation: CGSize
    ) -> NormalizedRect {
        var x = rect.x
        var y = rect.y
        var width = rect.width
        var height = rect.height

        switch corner {
        case .topLeading:
            x += translation.width
            y += translation.height
            width -= translation.width
            height -= translation.height
        case .topTrailing:
            y += translation.height
            width += translation.width
            height -= translation.height
        case .bottomLeading:
            x += translation.width
            width -= translation.width
            height += translation.height
        case .bottomTrailing:
            width += translation.width
            height += translation.height
        }

        return NormalizedRect(x: x, y: y, width: width, height: height)
    }
}
