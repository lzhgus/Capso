// Packages/EditorKit/Sources/EditorKit/FrameCompositor.swift

import CoreImage
import CoreGraphics
import Foundation

/// Composites a single video frame with optional zoom transform, cursor overlay,
/// and decorative background canvas.
///
/// `FrameCompositor` is a pure value-oriented pipeline — it holds no mutable state
/// and can safely be called from any actor or thread (hence `Sendable`).
public final class FrameCompositor: Sendable {

    // MARK: - Stored Properties

    private static let cursorHotspotXRatio: CGFloat = 0.12
    private static let cursorHotspotYRatio: CGFloat = 0.88

    private let sourceSize: CGSize
    private let backgroundStyle: BackgroundStyle
    private let scale: CGFloat

    // MARK: - Computed Properties

    /// The pixel dimensions of the composited output image.
    ///
    /// When `backgroundStyle.enabled` is `true` the canvas adds `2 × padding` to
    /// both axes (scaled by `outputScale`).  Dimensions are always rounded up to the
    /// nearest even integer so the result can be fed directly into a video encoder.
    public let outputSize: CGSize

    // MARK: - Init

    /// - Parameters:
    ///   - sourceSize: The pixel dimensions of the raw video frames.
    ///   - backgroundStyle: Background canvas configuration.
    ///   - outputScale: Display scale factor (e.g. 2.0 for Retina).  All padding /
    ///     radius values are multiplied by this factor before rendering.
    public init(sourceSize: CGSize, backgroundStyle: BackgroundStyle, outputScale: CGFloat) {
        self.sourceSize = sourceSize
        self.backgroundStyle = backgroundStyle
        self.scale = outputScale
        self.outputSize = Self.computeOutputSize(
            sourceSize: sourceSize,
            backgroundStyle: backgroundStyle,
            outputScale: outputScale
        )
    }

    // MARK: - Public API

    /// Composites one video frame and returns the resulting `CIImage`.
    ///
    /// The pipeline is:
    /// 1. Apply zoom transform (scale + translate) and crop back to source viewport.
    /// 2. Composite the cursor image at the given normalized position (if provided).
    /// 3. Optionally apply rounded corners.
    /// 4. Optionally add a drop shadow.
    /// 5. Composite the frame onto the background canvas.
    ///
    /// - Parameters:
    ///   - frame: Raw video frame.  Its `extent` should match `sourceSize`.
    ///   - zoomTransform: Scale + translation to apply before compositing.
    ///   - cursorPosition: Normalized (0–1, 0–1) position of the cursor in the source
    ///     frame.  Y=0 is the *top* of the frame (screen coordinate space); the
    ///     compositor flips to Core Image's bottom-left origin internally.
    ///   - cursorImage: The cursor image to overlay.  Its origin is placed at the
    ///     converted position.  Pass `nil` to skip cursor compositing.
    /// - Returns: The fully composited `CIImage` with extent starting at `(0, 0)` and
    ///   having dimensions equal to `outputSize`.
    public func compose(
        frame: CIImage,
        zoomTransform: FrameTransform,
        cursorPosition: CGPoint?,
        cursorImage: CIImage?
    ) -> CIImage {
        // 1. Zoom
        var result = applyZoom(to: frame, transform: zoomTransform)

        // 2. Cursor overlay — also passed the zoom transform so the cursor
        // lands on the zoomed content, not the original unzoomed position.
        if let position = cursorPosition, let cursor = cursorImage {
            result = applyCursor(cursor, at: position, zoomTransform: zoomTransform, over: result)
        }

        // 3 – 5. Background
        if backgroundStyle.enabled {
            result = applyBackground(to: result)
        }

        return result
    }

    // MARK: - Private: Zoom

    private func applyZoom(to image: CIImage, transform: FrameTransform) -> CIImage {
        guard transform != .identity else { return image }

        let w = sourceSize.width
        let h = sourceSize.height
        let s = CGFloat(transform.scale)

        // translateX/Y carry the normalized focus point (0-1) in screen coordinates
        // (top-left origin: x=0 left, y=0 top).
        // CIImage uses bottom-left origin, so flip Y.
        let focusX = CGFloat(transform.translateX) * w
        let focusY = (1.0 - CGFloat(transform.translateY)) * h
        let centerX = w / 2.0
        let centerY = h / 2.0

        // Scale around the focus point, then translate so focus appears at viewport center.
        // For point (px, py):
        //   1. (px - focusX, py - focusY)
        //   2. ((px - focusX) * s, (py - focusY) * s)
        //   3. ((px - focusX) * s + centerX, (py - focusY) * s + centerY)
        // → focus point (focusX, focusY) maps to (centerX, centerY) ✓
        let affine = CGAffineTransform.identity
            .translatedBy(x: centerX, y: centerY)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -focusX, y: -focusY)

        let zoomed = image.transformed(by: affine)

        // Crop back to the original source viewport so the output size stays fixed.
        let viewport = CGRect(x: 0, y: 0, width: w, height: h)
        return zoomed.cropped(to: viewport)
    }

    // MARK: - Private: Cursor

    private func applyCursor(
        _ cursor: CIImage,
        at position: CGPoint,
        zoomTransform: FrameTransform,
        over background: CIImage
    ) -> CIImage {
        let w = sourceSize.width
        let h = sourceSize.height

        // `position` uses top-left origin (screen coords); CIImage uses bottom-left.
        // Convert to the cursor's raw frame coordinates first.
        let origX = position.x * w
        let origY = (1.0 - position.y) * h

        // Zoom transforms the scene with: p_out = (p_in - focus) * s + center
        // The cursor must follow the same transform, otherwise it renders at
        // the UNZOOMED position and drifts away from the content it should be
        // attached to. The cursor image itself is also scaled by `s` so it
        // integrates visually with the zoomed scene.
        let s = CGFloat(zoomTransform.scale)
        let focusX = CGFloat(zoomTransform.translateX) * w
        let focusY = (1.0 - CGFloat(zoomTransform.translateY)) * h
        let centerX = w / 2.0
        let centerY = h / 2.0

        let x = (origX - focusX) * s + centerX
        let y = (origY - focusY) * s + centerY

        // Align the cursor hotspot (tip), not the image centre, to the tracked
        // position — hotspot offsets scale along with the image.
        let scaledCursor = cursor.transformed(by: CGAffineTransform(scaleX: s, y: s))
        let hotspotX = scaledCursor.extent.width * Self.cursorHotspotXRatio
        let hotspotY = scaledCursor.extent.height * Self.cursorHotspotYRatio
        let placed = scaledCursor.transformed(
            by: CGAffineTransform(translationX: x - hotspotX, y: y - hotspotY)
        )

        // Composite cursor over frame, clamped to source bounds.
        return placed.composited(over: background).cropped(to: background.extent)
    }

    // MARK: - Private: Background

    private func applyBackground(to frame: CIImage) -> CIImage {
        let padding = CGFloat(backgroundStyle.padding) * scale
        let canvasSize = outputSize
        let canvasRect = CGRect(origin: .zero, size: canvasSize)

        // Position the frame centred inside the canvas (padding on all four sides).
        let frameOrigin = CGPoint(x: padding, y: padding)
        let frameRect = CGRect(origin: frameOrigin, size: sourceSize)

        // 1. Optionally apply rounded corners to the frame image.
        let roundedFrame = applyRoundedCorners(to: frame, frameRect: frameRect)

        // 2. Optionally create a drop shadow underneath the frame.
        var composite: CIImage

        // 3. Build the background canvas.
        let canvas = buildCanvas(in: canvasRect, sourceFrame: frame)

        if backgroundStyle.shadowEnabled && backgroundStyle.shadowOpacity > 0 {
            let shadow = buildShadow(frameRect: frameRect)
            // shadow beneath canvas content, frame on top
            composite = roundedFrame
                .composited(over: shadow)
                .composited(over: canvas)
        } else {
            composite = roundedFrame.composited(over: canvas)
        }

        return composite.cropped(to: canvasRect)
    }

    /// Applies rounded corners to the frame by using `CIRoundedRectangleGenerator`
    /// as a mask via `CIBlendWithMask`.
    private func applyRoundedCorners(to frame: CIImage, frameRect: CGRect) -> CIImage {
        let clampedRadius = backgroundStyle.clampedCornerRadius(for: frameRect.size)
        let radius = CGFloat(clampedRadius) * scale
        guard radius > 0 else {
            // No rounding — just translate the frame to its canvas position.
            return frame.transformed(by: CGAffineTransform(translationX: frameRect.origin.x, y: frameRect.origin.y))
        }

        // Translate the frame to its position on the canvas.
        let positioned = frame.transformed(by: CGAffineTransform(translationX: frameRect.origin.x, y: frameRect.origin.y))

        // Build the rounded-rect mask.
        let mask = makeRoundedRectMask(rect: frameRect, radius: radius)

        // CIBlendWithMask: composites `inputImage` over `inputBackgroundImage` using `inputMaskImage`.
        // We want: `positioned` where mask is white, transparent elsewhere.
        let transparent = CIImage.empty()
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return positioned
        }
        blendFilter.setValue(positioned, forKey: kCIInputImageKey)
        blendFilter.setValue(transparent, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)
        return blendFilter.outputImage ?? positioned
    }

    /// Creates a white "squircle" (continuous-corner) `CIImage` alpha mask.
    ///
    /// The editor preview uses SwiftUI's `RoundedRectangle(style: .continuous)`
    /// which renders iOS-style squircle corners. `CIRoundedRectangleGenerator`
    /// and the stock `CGPath(roundedRect:cornerWidth:cornerHeight:)` path both
    /// produce classic 90° circular arcs, so preview and export used to
    /// disagree at the same radius value. Draw the mask with a custom
    /// Bezier path instead so both paths converge.
    private func makeRoundedRectMask(rect: CGRect, radius: CGFloat) -> CIImage {
        let w = Int(rect.width.rounded())
        let h = Int(rect.height.rounded())
        guard w > 0, h > 0 else { return CIImage.empty() }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return CIImage.empty() }

        ctx.setFillColor(gray: 1.0, alpha: 1.0)
        let localRect = CGRect(x: 0, y: 0, width: rect.width, height: rect.height)
        let path = Self.continuousRoundedRectPath(rect: localRect, cornerRadius: radius)
        ctx.addPath(path)
        ctx.fillPath()

        guard let cgImage = ctx.makeImage() else { return CIImage.empty() }
        let ci = CIImage(cgImage: cgImage)
        return ci.transformed(by: CGAffineTransform(translationX: rect.origin.x, y: rect.origin.y))
    }

    /// Approximates iOS's `.continuous` corner style (a squircle) using
    /// cubic Beziers. Each corner eases out ~1.528r before the vertex and
    /// eases back in ~1.528r after — a widely-cited reconstruction of
    /// Apple's continuous-corner curve. Falls back to a classic rounded
    /// rect when the radius is zero or the rect is too small to hold the
    /// full transition.
    static func continuousRoundedRectPath(rect: CGRect, cornerRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let maxR = min(rect.width, rect.height) / 2.0
        let r = min(max(0, cornerRadius), maxR)

        guard r > 0 else {
            path.addRect(rect)
            return path
        }

        // Transition length along each edge. Clamped so corners from two
        // adjacent edges can't overlap on very small rects.
        let t = min(r * 1.528, min(rect.width, rect.height) / 2.0)
        // Bezier handle length — places control points near the vertex so
        // the curve tucks in more tightly than a quarter-circle would.
        let k = r * 0.67

        let minX = rect.minX, maxX = rect.maxX
        let minY = rect.minY, maxY = rect.maxY

        // Top edge, moving right. Start after the top-left transition.
        path.move(to: CGPoint(x: minX + t, y: minY))
        path.addLine(to: CGPoint(x: maxX - t, y: minY))
        // Top-right corner.
        path.addCurve(
            to: CGPoint(x: maxX, y: minY + t),
            control1: CGPoint(x: maxX - k, y: minY),
            control2: CGPoint(x: maxX, y: minY + k)
        )
        // Right edge.
        path.addLine(to: CGPoint(x: maxX, y: maxY - t))
        // Bottom-right corner.
        path.addCurve(
            to: CGPoint(x: maxX - t, y: maxY),
            control1: CGPoint(x: maxX, y: maxY - k),
            control2: CGPoint(x: maxX - k, y: maxY)
        )
        // Bottom edge.
        path.addLine(to: CGPoint(x: minX + t, y: maxY))
        // Bottom-left corner.
        path.addCurve(
            to: CGPoint(x: minX, y: maxY - t),
            control1: CGPoint(x: minX + k, y: maxY),
            control2: CGPoint(x: minX, y: maxY - k)
        )
        // Left edge.
        path.addLine(to: CGPoint(x: minX, y: minY + t))
        // Top-left corner.
        path.addCurve(
            to: CGPoint(x: minX + t, y: minY),
            control1: CGPoint(x: minX, y: minY + k),
            control2: CGPoint(x: minX + k, y: minY)
        )
        path.closeSubpath()
        return path
    }

    // MARK: - Private: Shadow

    private func buildShadow(frameRect: CGRect) -> CIImage {
        let blurRadius = CGFloat(backgroundStyle.shadowRadius) * scale
        let opacity = CGFloat(backgroundStyle.shadowOpacity)

        // Create a solid-black rectangle matching the frame footprint.
        let shadowColor = CIColor(red: 0, green: 0, blue: 0, alpha: opacity)
        let blackRect = CIImage(color: shadowColor).cropped(to: frameRect)

        // Blur it to simulate a drop shadow.
        guard blurRadius > 0,
              let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return blackRect
        }
        // Clamp before blur to prevent edge artifacts
        let clamped = blackRect.clampedToExtent()
        blurFilter.setValue(clamped, forKey: kCIInputImageKey)
        blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)
        let blurred = blurFilter.outputImage ?? blackRect

        // The blur expands the image; crop it back to a reasonable bounding region.
        let expansion = blurRadius * 3
        let shadowRect = frameRect.insetBy(dx: -expansion, dy: -expansion)
        return blurred.cropped(to: shadowRect)
    }

    // MARK: - Private: Canvas

    private func buildCanvas(in rect: CGRect, sourceFrame: CIImage) -> CIImage {
        switch backgroundStyle.colorType {
        case .solid:
            let c = backgroundStyle.solidColor
            let color = CIColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
            return CIImage(color: color).cropped(to: rect)

        case .gradient:
            return buildGradientCanvas(in: rect)

        case .liquidGlass:
            return buildLiquidGlassCanvas(in: rect, sourceFrame: sourceFrame)
        }
    }

    /// Blurred, saturation-boosted copy of the source frame scaled to fill the canvas.
    private func buildLiquidGlassCanvas(in rect: CGRect, sourceFrame: CIImage) -> CIImage {
        let srcExtent = sourceFrame.extent
        guard srcExtent.width > 0, srcExtent.height > 0 else {
            return CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1)).cropped(to: rect)
        }

        // Aspect-fill scale with overshoot so blur edges stay inside canvas
        let coverScale = max(rect.width / srcExtent.width, rect.height / srcExtent.height) * 1.15
        var ci = sourceFrame.transformed(by: CGAffineTransform(scaleX: coverScale, y: coverScale))

        // Centre on canvas
        let tx = rect.midX - ci.extent.midX
        let ty = rect.midY - ci.extent.midY
        ci = ci.transformed(by: CGAffineTransform(translationX: tx, y: ty))

        // Boost saturation for richer glass-like colour bloom
        if let f = CIFilter(name: "CIColorControls", parameters: [
            kCIInputImageKey: ci,
            kCIInputSaturationKey: 1.9,
            kCIInputBrightnessKey: 0.0,
            kCIInputContrastKey: 0.95,
        ]), let out = f.outputImage {
            ci = out
        }

        // Clamp before blur to prevent edge fade
        let clamped = ci.clampedToExtent()
        if let f = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: clamped,
            kCIInputRadiusKey: 120.0,
        ]), let out = f.outputImage {
            ci = out
        }

        return ci.cropped(to: rect)
    }

    private func buildGradientCanvas(in rect: CGRect) -> CIImage {
        // Convert angle (degrees, 0 = top-to-bottom) to a start/end point pair.
        // Angle 0° → from top centre to bottom centre.
        let angleRad = CGFloat(backgroundStyle.gradientAngle) * .pi / 180.0

        let cx = rect.midX
        let cy = rect.midY
        // Half-diagonal so the gradient covers the full rect at any angle.
        let halfLen = hypot(rect.width, rect.height) / 2.0

        // `sin` drives X, `-cos` drives Y (angle 0 = straight down in screen space,
        // which is straight up in CIImage's flipped Y space → use +cos for CIImage Y).
        let dx = sin(angleRad) * halfLen
        let dy = cos(angleRad) * halfLen

        let point0 = CIVector(x: cx - dx, y: cy - dy)
        let point1 = CIVector(x: cx + dx, y: cy + dy)

        let from = backgroundStyle.gradientFrom
        let to   = backgroundStyle.gradientTo
        let color0 = CIColor(red: from.red, green: from.green, blue: from.blue, alpha: from.alpha)
        let color1 = CIColor(red: to.red,   green: to.green,   blue: to.blue,   alpha: to.alpha)

        guard let gradFilter = CIFilter(name: "CILinearGradient") else {
            // Fallback: solid color using gradientFrom.
            return CIImage(color: color0).cropped(to: rect)
        }
        gradFilter.setValue(point0, forKey: "inputPoint0")
        gradFilter.setValue(point1, forKey: "inputPoint1")
        gradFilter.setValue(color0, forKey: "inputColor0")
        gradFilter.setValue(color1, forKey: "inputColor1")

        let gradient = gradFilter.outputImage ?? CIImage(color: color0)
        return gradient.cropped(to: rect)
    }

    // MARK: - Private: Output size computation

    private static func computeOutputSize(
        sourceSize: CGSize,
        backgroundStyle: BackgroundStyle,
        outputScale: CGFloat
    ) -> CGSize {
        guard backgroundStyle.enabled else { return sourceSize }

        let padding = CGFloat(backgroundStyle.padding) * outputScale
        let rawWidth  = sourceSize.width  + 2 * padding
        let rawHeight = sourceSize.height + 2 * padding

        // Round up to even numbers (required by most video codecs).
        let w = CGFloat(Self.roundUpToEven(rawWidth))
        let h = CGFloat(Self.roundUpToEven(rawHeight))
        return CGSize(width: w, height: h)
    }

    /// Rounds a floating-point value up to the nearest even integer.
    private static func roundUpToEven(_ value: CGFloat) -> Int {
        let i = Int(ceil(value))
        return i % 2 == 0 ? i : i + 1
    }
}
