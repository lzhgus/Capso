import SwiftUI
import AVFoundation
import MetalKit
@preconcurrency import EditorKit

/// A SwiftUI view that wraps an `MTKView` to display a Metal-composited video preview.
///
/// Unlike `AVPlayerView`, this view runs every frame through `FrameCompositor`, which
/// applies zoom transforms, background styles, and cursor overlays in real time via
/// Core Image and Metal.
///
/// Usage: swap `EditorPreviewView` for `MetalPreviewView` in `RecordingEditorView`.
struct MetalPreviewView: NSViewRepresentable {

    // MARK: - Properties

    let player: AVPlayer
    let playerItem: AVPlayerItem
    let backgroundStyle: EditorKit.BackgroundStyle
    let zoomSegments: [ZoomSegment]
    let videoSize: CGSize
    let cursorTimeline: SmoothedCursorTimeline?
    let cursorCIImage: CIImage?
    let cursorOverlayProvider: CursorOverlayProvider?
    /// Corner radius applied directly to the MTKView's CALayer so the
    /// Metal texture itself is clipped evenly on all four sides. SwiftUI's
    /// `.clipShape` on an `NSViewRepresentable` backed by `CAMetalLayer`
    /// can leave one or two edges un-clipped — the layer-level fix uses
    /// `cornerCurve = .continuous` to keep the squircle shape.
    var cornerRadius: CGFloat = 0

    // MARK: - Coordinator

    @MainActor
    final class Coordinator {
        var renderer: MetalPreviewRenderer?
        var videoOutput: AVPlayerItemVideoOutput?
        weak var mtkView: MTKView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> NSView {
        // Container NSView holds the rounded-corner mask. SwiftUI's
        // `.clipShape` on a Metal-backed view leaks on some edges, so we
        // clip on the container's vanilla CALayer instead. Classic circular
        // corners (the default cornerCurve) match the Annotate tool's
        // look — that's the reference the user settled on.
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.masksToBounds = true
        container.layer?.isOpaque = false

        let view = MTKView()

        // Pixel format must match what CIContext expects when rendering to the texture.
        view.colorPixelFormat = .bgra8Unorm

        // CIContext.render(_:to:commandBuffer:...) requires write access to the texture,
        // which is blocked when framebufferOnly == true.
        view.framebufferOnly = false

        // Transparent background so letterbox areas show the window material, not black
        view.layer?.isOpaque = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        // Continuous rendering at ~30 fps — smooth enough for a preview without hammering GPU.
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 30

        // Build the AVPlayerItemVideoOutput that the renderer will poll each frame.
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        playerItem.add(videoOutput)
        context.coordinator.videoOutput = videoOutput

        // Create the renderer; if Metal is unavailable, leave delegate nil (black view).
        if let renderer = MetalPreviewRenderer(player: player, videoOutput: videoOutput) {
            renderer.updateCompositor(sourceSize: videoSize, backgroundStyle: backgroundStyle)
            renderer.updateZoom(segments: zoomSegments, frameSize: videoSize)
            renderer.updateCursorTimeline(cursorTimeline)
            renderer.updateCursor(image: cursorCIImage, provider: cursorOverlayProvider)
            view.device = MTLCreateSystemDefaultDevice()
            view.delegate = renderer
            context.coordinator.renderer = renderer
        }

        // Fill the container with the MTKView. The container's masksToBounds
        // handles the squircle clipping for us.
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.mtkView = view

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        renderer.updateCompositor(sourceSize: videoSize, backgroundStyle: backgroundStyle)
        renderer.updateZoom(segments: zoomSegments, frameSize: videoSize)
        renderer.updateCursorTimeline(cursorTimeline)
        renderer.updateCursor(image: cursorCIImage, provider: cursorOverlayProvider)
        // Keep container-level rounding in sync with the slider value.
        nsView.layer?.cornerRadius = cornerRadius
        nsView.layer?.masksToBounds = true
    }
}
