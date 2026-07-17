import Foundation
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// Core screenshot capture engine wrapping ScreenCaptureKit.
public enum ScreenCaptureManager {

    // MARK: - Fullscreen Capture

    public static func captureFullscreen(
        displayID: CGDirectDisplayID = CGMainDisplayID(),
        showsCursor: Bool = false
    ) async throws -> CaptureResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID })
            ?? content.displays.first(where: { $0.displayID == CGMainDisplayID() })
            ?? content.displays.first else {
            throw CaptureError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        // Use the display's actual point-to-pixel scale rather than hardcoding
        // @2x — otherwise a non-Retina external monitor gets captured at 2x its
        // native resolution (blurry upscale), and if Apple ever ships a @3x
        // display we silently under-sample.
        let scaleFactor = CGFloat(filter.pointPixelScale)
        config.width = Int(CGFloat(display.width) * scaleFactor)
        config.height = Int(CGFloat(display.height) * scaleFactor)
        config.captureResolution = .best
        config.showsCursor = showsCursor

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return CaptureResult(
            image: image,
            mode: .fullscreen,
            captureRect: display.frame,
            displayID: display.displayID
        )
    }

    // MARK: - Window Capture

    public static func captureWindow(
        windowID: CGWindowID,
        includeShadow: Bool = true,
        showsCursor: Bool = false
    ) async throws -> CaptureResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound(windowID)
        }

        // Find which display this window is on (needed for displayID metadata
        // and for the no-shadow display-based capture path).
        let windowCenter = CGPoint(x: scWindow.frame.midX, y: scWindow.frame.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(windowCenter) })
            ?? content.displays.first else {
            throw CaptureError.noDisplayFound
        }

        let filter: SCContentFilter
        let config = SCStreamConfiguration()
        config.captureResolution = .best
        config.showsCursor = showsCursor

        if includeShadow {
            // Desktop-independent window filter: ScreenCaptureKit renders the
            // window with its shadow on a transparent background. The filter's
            // contentRect automatically includes the shadow bounds.
            filter = SCContentFilter(desktopIndependentWindow: scWindow)
            config.ignoreShadowsSingleWindow = false
            let scaleFactor = CGFloat(filter.pointPixelScale)
            config.width = Int(filter.contentRect.width * scaleFactor)
            config.height = Int(filter.contentRect.height * scaleFactor)
        } else {
            // Display-based capture including only this window, cropped to the
            // window frame. This avoids the shadow and renders GPU content
            // in-place on the display (no distortion).
            filter = SCContentFilter(display: display, including: [scWindow])

            // `config.sourceRect` must be in the content filter's LOCAL
            // coordinate space — relative to the display's top-left at (0,0).
            var localRect = CGRect(
                x: scWindow.frame.origin.x - display.frame.origin.x,
                y: scWindow.frame.origin.y - display.frame.origin.y,
                width: scWindow.frame.width,
                height: scWindow.frame.height
            )
            let displayBounds = CGRect(x: 0, y: 0, width: display.frame.width, height: display.frame.height)
            localRect = localRect.intersection(displayBounds)
            guard !localRect.isEmpty else {
                throw CaptureError.captureFailed("Window is not visible on the target display")
            }
            config.sourceRect = localRect
            let scaleFactor = CGFloat(filter.pointPixelScale)
            config.width = Int(localRect.width * scaleFactor)
            config.height = Int(localRect.height * scaleFactor)
        }

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return CaptureResult(
            image: image,
            mode: .window,
            captureRect: scWindow.frame,
            windowName: scWindow.title,
            appName: scWindow.owningApplication?.applicationName,
            appBundleIdentifier: scWindow.owningApplication?.bundleIdentifier,
            displayID: display.displayID
        )
    }

    // MARK: - Multi-Window Capture

    /// Capture multiple windows and composite them onto a transparent canvas at
    /// their screen positions. `windowIDs` should be front-to-back (index 0 =
    /// frontmost) so overlapping windows stack correctly.
    ///
    /// Uses desktop-independent capture with shadows stripped so each layer
    /// keeps the WindowServer alpha silhouette (rounded corners). The
    /// display-based `includeShadow: false` path is intentionally avoided —
    /// it bakes an opaque rectangle and leaves white/jagged corner fringes.
    public static func captureWindows(
        windowIDs: [CGWindowID],
        showsCursor: Bool = false
    ) async throws -> CaptureResult {
        guard !windowIDs.isEmpty else {
            throw CaptureError.captureFailed("No windows selected")
        }

        var layers: [MultiWindowCompositor.Layer] = []
        layers.reserveCapacity(windowIDs.count)
        var displayID = CGMainDisplayID()

        for windowID in windowIDs {
            let result = try await captureWindowForMultiComposite(
                windowID: windowID,
                showsCursor: showsCursor
            )
            layers.append(MultiWindowCompositor.Layer(image: result.image, frame: result.captureRect))
            displayID = result.displayID
        }

        guard let union = MultiWindowCompositor.unionBounds(of: layers.map(\.frame)),
              let image = MultiWindowCompositor.composite(layers: layers) else {
            throw CaptureError.captureFailed("Failed to composite selected windows")
        }

        return CaptureResult(
            image: image,
            mode: .window,
            captureRect: union,
            windowName: "\(windowIDs.count) windows",
            appName: nil,
            appBundleIdentifier: nil,
            displayID: displayID
        )
    }

    /// Single-window capture tuned for multi-window compositing: transparent
    /// backdrop, real window alpha, no drop shadow (so frames stay aligned to
    /// `SCWindow.frame` for layout).
    private static func captureWindowForMultiComposite(
        windowID: CGWindowID,
        showsCursor: Bool
    ) async throws -> CaptureResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound(windowID)
        }

        let windowCenter = CGPoint(x: scWindow.frame.midX, y: scWindow.frame.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(windowCenter) })
            ?? content.displays.first else {
            throw CaptureError.noDisplayFound
        }

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()
        config.captureResolution = .best
        config.showsCursor = showsCursor
        // Keep the WindowServer alpha mask (rounded corners) but drop the
        // shadow so the bitmap lines up with `scWindow.frame` for compositing.
        config.ignoreShadowsSingleWindow = true
        // Size to the window frame (not contentRect) so the bitmap aspect
        // matches layout and we avoid stretch-induced edge fringe.
        let scaleFactor = CGFloat(filter.pointPixelScale)
        config.width = max(1, Int((scWindow.frame.width * scaleFactor).rounded()))
        config.height = max(1, Int((scWindow.frame.height * scaleFactor).rounded()))

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return CaptureResult(
            image: image,
            mode: .window,
            captureRect: scWindow.frame,
            windowName: scWindow.title,
            appName: scWindow.owningApplication?.applicationName,
            appBundleIdentifier: scWindow.owningApplication?.bundleIdentifier,
            displayID: display.displayID
        )
    }

    // MARK: - Desktop Background Capture (for window shadow compositing)

    /// Capture the desktop behind a window (excluding the window itself),
    /// cropped to the window area with extra padding for the shadow region.
    public static func captureDesktopBehindWindow(
        windowID: CGWindowID,
        padding: CGFloat
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound(windowID)
        }

        let windowCenter = CGPoint(x: scWindow.frame.midX, y: scWindow.frame.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(windowCenter) })
            ?? content.displays.first else {
            throw CaptureError.noDisplayFound
        }

        // Capture the entire display EXCLUDING the target window.
        let filter = SCContentFilter(display: display, excludingWindows: [scWindow])
        let config = SCStreamConfiguration()
        config.captureResolution = .best
        config.showsCursor = false

        // Crop to the window area + padding, in display-local coordinates.
        var cropRect = CGRect(
            x: scWindow.frame.origin.x - display.frame.origin.x - padding,
            y: scWindow.frame.origin.y - display.frame.origin.y - padding,
            width: scWindow.frame.width + padding * 2,
            height: scWindow.frame.height + padding * 2
        )
        let displayBounds = CGRect(x: 0, y: 0, width: display.frame.width, height: display.frame.height)
        cropRect = cropRect.intersection(displayBounds)
        guard !cropRect.isEmpty else {
            throw CaptureError.captureFailed("Window background is not visible")
        }

        config.sourceRect = cropRect
        let scaleFactor = CGFloat(filter.pointPixelScale)
        config.width = Int(cropRect.width * scaleFactor)
        config.height = Int(cropRect.height * scaleFactor)

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    // MARK: - Area Capture

    public static func captureArea(
        rect: CGRect,
        displayID: CGDirectDisplayID = CGMainDisplayID(),
        showsCursor: Bool = false
    ) async throws -> CaptureResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.captureResolution = .best
        config.showsCursor = showsCursor
        config.sourceRect = rect
        config.width = Int(rect.width) * 2
        config.height = Int(rect.height) * 2

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return CaptureResult(
            image: image,
            mode: .area,
            captureRect: rect,
            displayID: displayID
        )
    }
}

// MARK: - Errors

public enum CaptureError: Error, LocalizedError {
    case noDisplayFound
    case windowNotFound(CGWindowID)
    case capturePermissionDenied
    case captureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No display found for capture."
        case .windowNotFound(let id):
            return "Window with ID \(id) not found."
        case .capturePermissionDenied:
            return "Screen recording permission is required."
        case .captureFailed(let reason):
            return "Capture failed: \(reason)"
        }
    }
}
