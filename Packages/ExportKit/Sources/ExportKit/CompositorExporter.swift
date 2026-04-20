// Packages/ExportKit/Sources/ExportKit/CompositorExporter.swift

import Foundation
import AVFoundation
import CoreImage
import EditorKit
import SharedKit

/// A wrapper that lets a non-`Sendable` `CIImage` cross isolation boundaries.
///
/// `CIImage` is immutable at runtime and thread-safe to read from multiple
/// actors, but Apple hasn't annotated it as `Sendable`. The `@unchecked
/// Sendable` escape hatch is the recommended pattern for values that the
/// SDK will eventually mark `Sendable` but hasn't yet.
///
/// Why a wrapper instead of `sending CIImage?` on the parameter: Swift 6.0
/// (Xcode 16.4, used on CI) does region-based isolation analysis that
/// refuses to "send" a value whose source is a computed property on an
/// `@MainActor` class — the backing storage stays in the actor's region.
/// Wrapping in a `Sendable` type disconnects the region so the value can
/// cross to a nonisolated callee. Swift 6.3 (Xcode 26) relaxes this and
/// accepts the bare `sending` parameter, hence the local-passes-CI-fails
/// divergence we hit.
public struct SendableCIImage: @unchecked Sendable {
    public let image: CIImage?
    public init(_ image: CIImage?) { self.image = image }
}

/// Exports a recording with visual effects (background, zoom) baked in.
///
/// Uses `AVMutableVideoComposition` with a CIFilter handler for per-frame
/// compositing via `FrameCompositor`. Audio is passed through automatically
/// by `AVAssetExportSession`.
public enum CompositorExporter {

    public static func export(
        source: URL,
        project: RecordingProject,
        cursorTimeline: SmoothedCursorTimeline?,
        zoomInterpolator: ZoomInterpolator?,
        cursorImage: SendableCIImage = SendableCIImage(nil),
        cursorOverlayProvider: CursorOverlayProvider? = nil,
        destination: URL,
        quality: ExportQuality,
        progress: (@Sendable (Double) -> Void)? = nil,
        status: (@Sendable (ExportStatus) -> Void)? = nil
    ) async throws -> URL {

        let cursorImage = cursorImage.image
        status?(ExportStatus(stage: .preparing, fractionCompleted: 0))

        let asset = AVURLAsset(url: source)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ExportError.frameExtractionFailed
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let nominalFPS = try await videoTrack.load(.nominalFrameRate)
        let fps = nominalFPS > 0 ? nominalFPS : 30.0

        let compositor = FrameCompositor(
            sourceSize: naturalSize,
            backgroundStyle: project.backgroundStyle,
            outputScale: 1.0
        )
        status?(ExportStatus(stage: .compositing, fractionCompleted: 0.08))
        let outSize = compositor.outputSize
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])

        // Build the video composition with per-frame CIFilter handler
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = outSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        // Use the customVideoCompositorClass approach is complex; instead use
        // the simpler CIFilter handler. But we must create it properly.
        let filterComposition = try await AVMutableVideoComposition.videoComposition(
            with: asset,
            applyingCIFiltersWithHandler: { request in
                let sourceImage = request.sourceImage
                let timeSec = request.compositionTime.seconds
                let sourceRect = CGRect(origin: .zero, size: naturalSize)

                // Compute zoom
                let cursorPos = cursorTimeline?.position(at: timeSec)
                let zoomTransform: FrameTransform
                if let interp = zoomInterpolator {
                    let cp = cursorPos.map { (x: $0.x, y: $0.y) }
                    zoomTransform = interp.transform(at: timeSec, cursorPosition: cp)
                } else {
                    zoomTransform = .identity
                }

                // Compute click-scaled cursor image
                var scaledCursor: CIImage? = nil
                if let cursorImg = cursorImage {
                    let clickScale = cursorOverlayProvider?.clickScale(at: timeSec) ?? 1.0
                    if clickScale < 1.0 {
                        let cs = CGFloat(clickScale)
                        scaledCursor = cursorImg.transformed(by: CGAffineTransform(scaleX: cs, y: cs))
                    } else {
                        scaledCursor = cursorImg
                    }
                }

                // Composite
                let cgCursorPos = cursorPos.map { CGPoint(x: $0.x, y: $0.y) }
                let composited = compositor.compose(
                    frame: sourceImage.cropped(to: sourceRect),
                    zoomTransform: zoomTransform,
                    cursorPosition: cgCursorPos,
                    cursorImage: scaledCursor
                )

                // Ensure output extent starts at origin and matches renderSize
                let outputRect = CGRect(origin: .zero, size: outSize)
                let finalImage = composited.cropped(to: outputRect)

                request.finish(with: finalImage, context: ciContext)
            }
        )

        // Override renderSize and frameDuration on the composition returned by
        // the convenience initializer (it defaults to naturalSize)
        filterComposition.renderSize = outSize
        filterComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        // Export preset
        let presetName = switch quality {
        case .maximum: AVAssetExportPresetHighestQuality
        case .social: AVAssetExportPreset1920x1080
        case .web: AVAssetExportPreset1280x720
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw ExportError.exportSessionFailed("Could not create export session")
        }

        session.videoComposition = filterComposition
        session.shouldOptimizeForNetworkUse = true

        // Apply trim
        let sortedTrims = project.trimRegions.sorted { $0.startTime < $1.startTime }
        let effectiveStart = sortedTrims.filter { $0.startTime < 0.01 }.map(\.endTime).max() ?? 0
        let duration = try await asset.load(.duration).seconds
        let effectiveEnd = sortedTrims.filter { $0.endTime >= duration - 0.01 }.map(\.startTime).min() ?? duration

        if effectiveStart > 0.01 || effectiveEnd < duration - 0.01 {
            let cmStart = CMTime(seconds: effectiveStart, preferredTimescale: 600)
            let cmDuration = CMTime(seconds: effectiveEnd - effectiveStart, preferredTimescale: 600)
            session.timeRange = CMTimeRange(start: cmStart, duration: cmDuration)
            status?(ExportStatus(stage: .trimming, fractionCompleted: 0.12))
        }

        try? FileManager.default.removeItem(at: destination)

        do {
            try await session.export(to: destination, as: .mp4)
        } catch is CancellationError {
            throw ExportError.cancelled
        } catch {
            throw ExportError.exportSessionFailed(error.localizedDescription)
        }

        status?(ExportStatus(stage: .finalizing, fractionCompleted: 1.0))
        progress?(1.0)
        return destination
    }

}
