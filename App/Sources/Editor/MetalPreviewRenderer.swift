import AVFoundation
import CoreImage
import CoreVideo
import Metal
import MetalKit
@preconcurrency import EditorKit

/// Real-time Metal-backed preview renderer for the recording editor.
///
/// Implements `MTKViewDelegate` to drive frame compositing on every display-refresh tick.
/// The pipeline is:
///   `AVPlayerItemVideoOutput → CVPixelBuffer → CIImage → FrameCompositor → CIContext → MTKView drawable`
///
/// Because `MTKViewDelegate` methods are `nonisolated` protocol requirements but MTKView
/// always calls `draw(in:)` on the main thread, we use `MainActor.assumeIsolated` inside
/// that method to safely access `@MainActor`-isolated state without a suspension point.
@MainActor
final class MetalPreviewRenderer: NSObject {

    // MARK: - Metal / CI infrastructure

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext

    // MARK: - Playback sources

    private let player: AVPlayer
    private let videoOutput: AVPlayerItemVideoOutput

    // MARK: - Compositing state (mutated only on MainActor)

    private var compositor: FrameCompositor?
    private var zoomInterpolator: ZoomInterpolator?
    private var cursorTimeline: SmoothedCursorTimeline?
    private var cursorCIImage: CIImage?
    private var cursorOverlayProvider: CursorOverlayProvider?

    /// Last raw (unprocessed) frame — kept so we can re-composite when settings change while paused.
    private var lastRawFrame: CIImage?
    /// Last composited frame — displayed when paused and settings haven't changed.
    private var lastCompositedFrame: CIImage?
    /// Set to true when compositor/zoom/cursor settings change, forcing a re-composite of lastRawFrame.
    private var needsRecomposite = false

    // MARK: - Init

    /// Returns `nil` when no Metal device is available (e.g., CI simulator).
    init?(player: AVPlayer, videoOutput: AVPlayerItemVideoOutput) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue()
        else { return nil }

        self.device = device
        self.commandQueue = commandQueue
        self.player = player
        self.videoOutput = videoOutput

        // GPU-backed CIContext — shares the same Metal device as the MTKView so we can
        // render directly into the drawable texture without any extra copy.
        self.ciContext = CIContext(
            mtlDevice: device,
            options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()]
        )
    }

    // MARK: - Public API

    /// Creates (or recreates) the `FrameCompositor` when source size or background changes.
    func updateCompositor(sourceSize: CGSize, backgroundStyle: EditorKit.BackgroundStyle) {
        compositor = FrameCompositor(
            sourceSize: sourceSize,
            backgroundStyle: backgroundStyle,
            outputScale: 1.0
        )
        needsRecomposite = true
    }

    /// Rebuilds the zoom interpolator when segments or frame size change.
    func updateZoom(segments: [ZoomSegment], frameSize: CGSize) {
        zoomInterpolator = segments.isEmpty
            ? nil
            : ZoomInterpolator(segments: segments, frameSize: frameSize)
        needsRecomposite = true
    }

    /// Replaces the cursor timeline used to composite cursor overlays.
    func updateCursorTimeline(_ timeline: SmoothedCursorTimeline?) {
        cursorTimeline = timeline
        needsRecomposite = true
    }

    /// Updates the cursor image and click-shrink provider used for cursor rendering.
    func updateCursor(image: CIImage?, provider: CursorOverlayProvider?) {
        self.cursorCIImage = image
        self.cursorOverlayProvider = provider
        needsRecomposite = true
    }

    // MARK: - Frame rendering

    /// Core rendering work — pulls a pixel buffer, composites it, and blits it to the drawable.
    /// Must be called on the main thread.
    private func renderFrame(in view: MTKView) {
        // 1. Obtain a drawable. Bail early if Metal isn't ready.
        guard
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        let drawableSize = view.drawableSize
        guard drawableSize.width > 0, drawableSize.height > 0 else { return }

        // 2. Pull a fresh CVPixelBuffer from the video output, if one is available.
        let currentTime = player.currentTime()
        var rawFrame: CIImage?

        if videoOutput.hasNewPixelBuffer(forItemTime: currentTime),
           let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) {
            rawFrame = CIImage(cvPixelBuffer: pixelBuffer)
            lastRawFrame = rawFrame
            needsRecomposite = true // new frame always needs compositing
        } else if needsRecomposite {
            // Settings changed while paused — re-composite from cached raw frame
            rawFrame = lastRawFrame
        }

        let frameImage: CIImage
        if let raw = rawFrame {
            // Composite via FrameCompositor
            if let comp = compositor {
                let time = currentTime.seconds

                var cursorPos: CGPoint? = nil
                if let timeline = cursorTimeline {
                    let pos = timeline.position(at: time)
                    cursorPos = CGPoint(x: pos.x, y: pos.y)
                }

                let zoomTransform: FrameTransform
                if let interp = zoomInterpolator {
                    let cursorTuple = cursorPos.map { (x: Double($0.x), y: Double($0.y)) }
                    zoomTransform = interp.transform(at: time, cursorPosition: cursorTuple)
                } else {
                    zoomTransform = .identity
                }

                // Compute click-scaled cursor image
                var scaledCursor: CIImage? = nil
                if let cursorImg = cursorCIImage {
                    let clickScale = cursorOverlayProvider?.clickScale(at: time) ?? 1.0
                    if clickScale < 1.0 {
                        let cs = CGFloat(clickScale)
                        scaledCursor = cursorImg.transformed(by: CGAffineTransform(scaleX: cs, y: cs))
                    } else {
                        scaledCursor = cursorImg
                    }
                }

                frameImage = comp.compose(
                    frame: raw,
                    zoomTransform: zoomTransform,
                    cursorPosition: cursorPos,
                    cursorImage: scaledCursor
                )
            } else {
                frameImage = raw
            }

            lastCompositedFrame = frameImage
            needsRecomposite = false
        } else if let cached = lastCompositedFrame {
            // Nothing changed — reuse last composited frame
            frameImage = cached
        } else {
            // Nothing to show yet
            commandBuffer.commit()
            return
        }

        // 4. Aspect-fit the composited image into the drawable bounds.
        let src = frameImage.extent
        let dst = CGRect(origin: .zero, size: drawableSize)

        guard src.width > 0, src.height > 0 else {
            commandBuffer.commit()
            return
        }

        let scale = min(dst.width / src.width, dst.height / src.height)
        let scaledW = src.width  * scale
        let scaledH = src.height * scale
        let tx = dst.midX - scaledW / 2
        let ty = dst.midY - scaledH / 2

        let aspectFit = frameImage
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: tx, y: ty))

        // 5. Render to the Metal drawable texture. Zero-copy path — CIContext writes
        //    directly into the drawable's MTLTexture via the shared command buffer.
        let texture = drawable.texture
        ciContext.render(
            aspectFit,
            to: texture,
            commandBuffer: commandBuffer,
            bounds: dst,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - MTKViewDelegate

extension MetalPreviewRenderer: MTKViewDelegate {

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // No stored size — drawableSize is read fresh each frame from view.drawableSize.
    }

    nonisolated func draw(in view: MTKView) {
        // MTKView calls this on the main thread when isPaused == false.
        // MainActor.assumeIsolated lets us access @MainActor state without an async hop.
        MainActor.assumeIsolated {
            renderFrame(in: view)
        }
    }
}
