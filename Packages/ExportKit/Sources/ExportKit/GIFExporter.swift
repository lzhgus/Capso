// Packages/ExportKit/Sources/ExportKit/GIFExporter.swift
import Foundation
import AVFoundation
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import SharedKit

enum GIFExporter {
    /// Encode a source `.mov` recording to an animated GIF.
    ///
    /// Decodes the source video sequentially via `AVAssetReader`, samples
    /// the decoded stream down to a target frame rate, and writes each
    /// kept frame to a `CGImageDestination`. Per-frame delays are computed
    /// from the actual presentation-time gap between consecutive emitted
    /// frames, so the resulting GIF's total duration always matches the
    /// source — even when the source has uneven frame timing or content
    /// gaps (e.g. screen recordings of mostly-static text where the
    /// screen-capture stream emits frames only when something changes).
    ///
    /// Each emitted frame is rendered into a *standalone*, CPU-backed
    /// CGImage whose memory we malloc/free explicitly. The GIF encoder's
    /// finalize step (`ColorQuantization::hist3d`) walks the pixel data of
    /// every frame at the very end; if any frame's backing memory has
    /// been freed or evicted from a GPU/CIContext cache by then, the
    /// encoder crashes with EXC_BAD_ACCESS deep inside ImageIO. We avoid
    /// that entirely by owning the bytes ourselves.
    static func export(
        source: URL,
        quality: ExportQuality,
        destination: URL,
        progress: (@Sendable (Double) -> Void)?,
        status: (@Sendable (ExportStatus) -> Void)?
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)
        status?(ExportStatus(stage: .preparing, fractionCompleted: 0))

        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            throw ExportError.frameExtractionFailed
        }
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0 else { throw ExportError.frameExtractionFailed }

        // Quality presets — we keep both per-frame area AND total frame
        // count bounded so the GIF encoder's colour-quantisation pass
        // (which scans every emitted frame at the end) doesn't blow up
        // on long high-resolution recordings.
        let baseFps: Double
        let maxWidth: CGFloat
        switch quality {
        case .maximum:
            baseFps = 25
            maxWidth = 1920
        case .social:
            baseFps = 20
            maxWidth = 1080
        case .web:
            baseFps = 15
            maxWidth = 720
        }

        // Hard cap on total emitted frames. Beyond this, drop fps
        // proportionally so very long recordings still encode. The cap
        // is empirical: ImageIO's GIF encoder gets unstable above a few
        // thousand frames at typical Retina resolutions.
        let maxTotalFrames = 600
        let estimatedRawFrameCount = max(1, Int(ceil(totalSeconds * baseFps)))
        let targetFps: Double
        if estimatedRawFrameCount > maxTotalFrames {
            targetFps = Double(maxTotalFrames) / totalSeconds
        } else {
            targetFps = baseFps
        }
        let estimatedFrameCount = max(1, Int(ceil(totalSeconds * targetFps)))
        status?(ExportStatus(stage: .encoding, fractionCompleted: 0.08))

        // Load the video track.
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ExportError.frameExtractionFailed
        }

        // AVAssetReader for sequential decoding into BGRA pixel buffers.
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw ExportError.frameExtractionFailed
        }

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        // Always copy: we copy the data ourselves into a malloc'd buffer
        // immediately, so this isn't strictly required, but defending in
        // depth in case the recycled IOSurface is in use during draw.
        trackOutput.alwaysCopiesSampleData = true
        guard reader.canAdd(trackOutput) else {
            throw ExportError.frameExtractionFailed
        }
        reader.add(trackOutput)

        guard reader.startReading() else {
            throw ExportError.frameExtractionFailed
        }

        // Open the GIF destination.
        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0,    // infinite loop
            ]
        ]
        guard let dest = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.gif.identifier as CFString,
            estimatedFrameCount,
            nil
        ) else {
            throw ExportError.gifCreationFailed
        }
        CGImageDestinationSetProperties(dest, fileProperties as CFDictionary)

        // Subsample to target fps and emit frames with their actual
        // presentation-time gaps as the GIF delay (so the GIF's total
        // duration always matches the source).
        let targetInterval = 1.0 / targetFps
        let minGifDelay = 0.02
        var nextSampleTime: Double = 0
        var pendingImage: CGImage?
        var pendingTime: Double = 0
        var emittedCount = 0
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        while reader.status == .reading {
            guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else { break }

            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            guard pts.isFinite else { continue }

            // Subsample to target fps using `+= interval` (drift-tolerant
            // greedy keep). For dense sources this gives an even subsample;
            // for sparse sources it always emits the next available frame.
            if pts < nextSampleTime { continue }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            guard let cgImage = makeStandaloneCGImage(
                from: pixelBuffer,
                maxWidth: maxWidth,
                colorSpace: sRGB
            ) else { continue }

            // Flush the previously-held frame with its true on-screen delay.
            if let prev = pendingImage {
                let delay = max(minGifDelay, pts - pendingTime)
                addGifFrame(dest: dest, image: prev, delay: delay)
                emittedCount += 1
            }

            pendingImage = cgImage
            pendingTime = pts
            nextSampleTime += targetInterval

            progress?(min(0.99, pts / totalSeconds))
            status?(ExportStatus(stage: .encoding, fractionCompleted: min(0.99, pts / totalSeconds)))
        }

        if reader.status == .failed {
            throw ExportError.frameExtractionFailed
        }

        // Flush the final pending frame with one target-interval delay.
        if let last = pendingImage {
            addGifFrame(dest: dest, image: last, delay: max(minGifDelay, targetInterval))
            emittedCount += 1
        }

        guard emittedCount > 0 else { throw ExportError.frameExtractionFailed }

        guard CGImageDestinationFinalize(dest) else {
            throw ExportError.gifCreationFailed
        }

        status?(ExportStatus(stage: .finalizing, fractionCompleted: 1.0))
        progress?(1.0)
        return destination
    }

    /// Convert a `CVPixelBuffer` (BGRA from AVAssetReader) into a fully
    /// self-contained CGImage with its own malloc'd RGBA8 sRGB pixel
    /// buffer.
    ///
    /// The returned CGImage:
    /// - has its own backing bytes in normal heap memory
    /// - does NOT reference the source `CVPixelBuffer` after this
    ///   function returns (the buffer is unlocked via `defer`)
    /// - does NOT depend on a `CIContext` cache, Metal heap, or any
    ///   GPU resource — pure Quartz 2D copy
    ///
    /// Lifetime chain: returned CGImage → CGDataProvider → malloc'd
    /// buffer. The transient CGContext used to perform the draw is
    /// released right after this function returns; that's harmless
    /// because it never owned the bytes.
    private static func makeStandaloneCGImage(
        from pixelBuffer: CVPixelBuffer,
        maxWidth: CGFloat,
        colorSpace: CGColorSpace
    ) -> CGImage? {
        let srcWidth = CVPixelBufferGetWidth(pixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard srcWidth > 0, srcHeight > 0 else { return nil }

        // Compute destination dimensions (downscale only — never upscale).
        let scaleFactor: CGFloat
        if maxWidth > 0 && CGFloat(srcWidth) > maxWidth {
            scaleFactor = maxWidth / CGFloat(srcWidth)
        } else {
            scaleFactor = 1.0
        }
        let dstWidth = max(1, Int(round(CGFloat(srcWidth) * scaleFactor)))
        let dstHeight = max(1, Int(round(CGFloat(srcHeight) * scaleFactor)))

        // Lock the pixel buffer for read so we can build a temporary
        // source CGImage that views its memory.
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Borrowed-data provider for the source image. Its release
        // callback is a no-op because the bytes belong to the
        // CVPixelBuffer (we don't own them).
        guard let srcProvider = CGDataProvider(
            dataInfo: nil,
            data: baseAddress,
            size: srcBytesPerRow * srcHeight,
            releaseData: { _, _, _ in /* no-op: borrowed memory */ }
        ) else { return nil }

        // Source CGImage in BGRA8 layout — matches kCVPixelFormatType_32BGRA.
        let srcBitmapInfo: UInt32 =
            CGBitmapInfo.byteOrder32Little.rawValue |
            CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let srcImage = CGImage(
            width: srcWidth,
            height: srcHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: srcBytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: srcBitmapInfo),
            provider: srcProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        // Allocate the destination buffer ourselves. Lifetime is then
        // bound to the CGDataProvider we build below — no shared data
        // with any CGContext, no GPU references.
        let dstBytesPerRow = dstWidth * 4
        let dstByteCount = dstBytesPerRow * dstHeight
        guard let dstBuffer = malloc(dstByteCount) else { return nil }

        // Render the source into our buffer via a transient CGContext.
        // RGBA8 byte layout (R first byte, A last byte) — what most
        // image consumers, including the GIF encoder, expect.
        let dstBitmapInfo: UInt32 =
            CGBitmapInfo.byteOrder32Big.rawValue |
            CGImageAlphaInfo.premultipliedLast.rawValue
        guard let dstContext = CGContext(
            data: dstBuffer,
            width: dstWidth,
            height: dstHeight,
            bitsPerComponent: 8,
            bytesPerRow: dstBytesPerRow,
            space: colorSpace,
            bitmapInfo: dstBitmapInfo
        ) else {
            free(dstBuffer)
            return nil
        }
        dstContext.interpolationQuality = .high
        dstContext.draw(srcImage, in: CGRect(x: 0, y: 0, width: dstWidth, height: dstHeight))

        // Wrap the buffer in a data provider that frees it when the
        // CGImage is finally released. From this point on the buffer is
        // OWNED by the provider — we must not call free() ourselves.
        guard let dstProvider = CGDataProvider(
            dataInfo: nil,
            data: dstBuffer,
            size: dstByteCount,
            releaseData: { _, data, _ in
                free(UnsafeMutableRawPointer(mutating: data))
            }
        ) else {
            free(dstBuffer)
            return nil
        }

        return CGImage(
            width: dstWidth,
            height: dstHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: dstBytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: dstBitmapInfo),
            provider: dstProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func addGifFrame(dest: CGImageDestination, image: CGImage, delay: Double) {
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: delay,
                kCGImagePropertyGIFUnclampedDelayTime as String: delay,
            ]
        ]
        CGImageDestinationAddImage(dest, image, frameProperties as CFDictionary)
    }
}
