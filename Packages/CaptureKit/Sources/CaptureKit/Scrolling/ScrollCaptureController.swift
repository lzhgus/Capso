// Packages/CaptureKit/Sources/CaptureKit/Scrolling/ScrollCaptureController.swift
import CoreGraphics
import Foundation
import Vision
@preconcurrency import ScreenCaptureKit

public struct ScrollCaptureConfig: Sendable {
    public let captureRect: CGRect
    public let displayID: CGDirectDisplayID
    public let mode: ScrollMode
    public let maxHeight: Int

    public init(
        captureRect: CGRect,
        displayID: CGDirectDisplayID,
        mode: ScrollMode = .manual,
        maxHeight: Int = 30_000
    ) {
        self.captureRect = captureRect
        self.displayID = displayID
        self.mode = mode
        self.maxHeight = maxHeight
    }
}

public enum ScrollMode: Sendable {
    case auto
    case manual
}

public struct ScrollCaptureProgress: Sendable {
    public let currentHeight: Int
    public let maxHeight: Int
    public let frameCount: Int
}

public final class ScrollCaptureController: @unchecked Sendable {
    private let config: ScrollCaptureConfig
    private let stitcher = ScrollStitcher()
    private var isCancelled = false
    private var frameCount = 0

    /// A/B frame model
    private var shotA: CGImage?

    /// Cached ScreenCaptureKit objects (created once, reused)
    private var cachedFilter: SCContentFilter?
    private var cachedStreamConfig: SCStreamConfiguration?

    public var currentMergedImage: CGImage? { stitcher.mergedImage }

    public init(config: ScrollCaptureConfig) {
        self.config = config
    }

    public func start(
        onProgress: @escaping @Sendable (ScrollCaptureProgress) -> Void,
        onComplete: @escaping @Sendable (CGImage?) -> Void
    ) {
        Task.detached(priority: .utility) { [self] in
            let result = await self.runCaptureLoop(onProgress: onProgress)
            onComplete(result)
        }
    }

    public func stop() {
        isCancelled = true
    }

    // MARK: - Capture Loop

    private func runCaptureLoop(
        onProgress: @escaping @Sendable (ScrollCaptureProgress) -> Void
    ) async -> CGImage? {
        // Capture initial frame
        guard let firstFrame = await captureFrame() else {
            return nil
        }
        stitcher.setInitialFrame(firstFrame)
        shotA = firstFrame
        frameCount = 1

        onProgress(ScrollCaptureProgress(
            currentHeight: stitcher.totalHeight,
            maxHeight: config.maxHeight,
            frameCount: frameCount
        ))

        // Main capture loop — runs until user clicks Done (isCancelled)
        // or max height is reached. No auto-stop on pause/jitter.
        while !isCancelled {
            if stitcher.totalHeight >= config.maxHeight { break }

            try? await Task.sleep(for: .milliseconds(150))
            guard !isCancelled else { break }

            guard let shotB = await captureFrame() else { continue }

            // Skip if identical (user not scrolling)
            if let dataA = shotA?.dataProvider?.data,
               let dataB = shotB.dataProvider?.data,
               CFDataGetLength(dataA) == CFDataGetLength(dataB),
               memcmp(CFDataGetBytePtr(dataA)!, CFDataGetBytePtr(dataB)!, CFDataGetLength(dataA)) == 0 {
                continue
            }

            guard let rawOffset = detectOffset(imageA: shotA!, imageB: shotB) else {
                shotA = shotB
                continue
            }

            let absOffset = abs(rawOffset)
            if absOffset < 3 { continue }

            let result = stitcher.stitch(newFrame: shotB, detectedOffset: absOffset)

            if case .stitched = result {
                frameCount += 1
                onProgress(ScrollCaptureProgress(
                    currentHeight: stitcher.totalHeight,
                    maxHeight: config.maxHeight,
                    frameCount: frameCount
                ))
            }

            shotA = shotB
        }

        return stitcher.mergedImage
    }

    // MARK: - Frame Capture

    private func captureFrame() async -> CGImage? {
        do {
            if cachedFilter == nil {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )
                guard let display = content.displays.first(where: {
                    $0.displayID == config.displayID
                }) ?? content.displays.first else {
                    return nil
                }

                let excludedBundleIDs: Set<String> = [
                    Bundle.main.bundleIdentifier ?? "",
                    "com.apple.dock",
                    "com.apple.controlcenter",
                    "com.apple.notificationcenterui",
                    "com.apple.Spotlight",
                ]
                let excludedWindows = content.windows.filter { window in
                    guard let bundleID = window.owningApplication?.bundleIdentifier else {
                        return false
                    }
                    return excludedBundleIDs.contains(bundleID)
                }

                let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
                let streamConfig = SCStreamConfiguration()
                streamConfig.captureResolution = .best
                streamConfig.showsCursor = false
                streamConfig.sourceRect = config.captureRect
                let scale = CGFloat(filter.pointPixelScale)
                streamConfig.width = Int(config.captureRect.width * scale)
                streamConfig.height = Int(config.captureRect.height * scale)

                cachedFilter = filter
                cachedStreamConfig = streamConfig
            }

            guard let filter = cachedFilter, let cfg = cachedStreamConfig else {
                return nil
            }

            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: cfg
            )
        } catch {
            return nil
        }
    }

    // MARK: - Vision Offset Detection

    /// Detect Y offset between two frames using VNTranslationalImageRegistrationRequest.
    /// Each call creates a fresh VNImageRequestHandler (stateless, reliable).
    private func detectOffset(imageA: CGImage, imageB: CGImage) -> Int? {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: imageA)
        let handler = VNImageRequestHandler(cgImage: imageB, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first
                as? VNImageTranslationAlignmentObservation else {
            return nil
        }

        let ty = observation.alignmentTransform.ty
        return Int(round(ty))
    }
}
