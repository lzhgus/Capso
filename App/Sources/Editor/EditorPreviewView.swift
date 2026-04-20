import SwiftUI
import AVKit
@preconcurrency import EditorKit

/// Video preview with real-time zoom (Metal) + background effects (SwiftUI).
///
/// Architecture:
/// - Zoom: rendered in real-time via MetalPreviewView (AVPlayerItemVideoOutput → CIImage → FrameCompositor zoom only → MTKView)
/// - Background: SwiftUI decorations (padding, color, shadow, corners) — reliable and flicker-free
///
/// The FrameCompositor in the Metal renderer is configured with background DISABLED
/// so it only applies zoom transforms. Background styling is handled by the SwiftUI layer.
struct EditorPreviewView: View {
    let coordinator: EditorCoordinator

    private var bg: EditorKit.BackgroundStyle {
        coordinator.project.backgroundStyle
    }

    private var frameCornerRadius: CGFloat {
        CGFloat(bg.clampedCornerRadius(for: coordinator.project.videoSize))
    }

    /// Video aspect ratio for constraining the preview area
    private var videoAspectRatio: CGFloat {
        let size = coordinator.project.videoSize
        guard size.height > 0 else { return 16.0 / 9.0 }
        return size.width / size.height
    }

    /// Aspect ratio including background padding
    private var compositeAspectRatio: CGFloat {
        let size = coordinator.project.videoSize
        guard size.height > 0 else { return 16.0 / 9.0 }
        let pad = bg.padding * 2
        return (size.width + pad) / (size.height + pad)
    }

    var body: some View {
        // Compute preview→source scale so corner radius, padding and shadow
        // — all stored in SOURCE-pixel units to match the export compositor
        // — can be rendered in view points. Without this, the preview shows
        // a different-sized corner than what the exported video contains,
        // and the slider max is pinned to the preview's view-point range
        // instead of the source's pixel range.
        if bg.enabled {
            GeometryReader { proxy in
                let compositeSourceWidth = coordinator.project.videoSize.width + bg.padding * 2
                let displayScale: CGFloat = compositeSourceWidth > 0
                    ? proxy.size.width / compositeSourceWidth
                    : 1.0
                previewWithBackground(displayScale: displayScale)
            }
            .aspectRatio(compositeAspectRatio, contentMode: .fit)
        } else {
            GeometryReader { proxy in
                let sourceWidth = coordinator.project.videoSize.width
                let displayScale: CGFloat = sourceWidth > 0
                    ? proxy.size.width / sourceWidth
                    : 1.0
                metalPreview(cornerRadius: 4 * displayScale)
            }
            .aspectRatio(videoAspectRatio, contentMode: .fit)
        }
    }

    // NOTE on corner style: the Annotate tool is the user's reference.
    // Annotate's outer "beautifyBackground" is a plain Rectangle() with NO
    // corner clipping — only the inner image gets rounded corners. We
    // previously tried a rounded outer frame (cornerRadius: 8 then 12);
    // at small padding, that extra outer arc visually competed with the
    // inner image's rounding, and the user correctly identified this as
    // "not like Annotate." Match Annotate's structure exactly:
    //
    //   ZStack {
    //     flat background rectangle  // no clipShape
    //     inner image
    //       .clipShape(RoundedRectangle(cornerRadius: slider))
    //       .shadow(...)
    //       .padding(bg.padding)
    //   }

    /// Metal preview configured for zoom-only (no background compositing).
    ///
    /// Corner rounding is applied INSIDE `MetalPreviewView` at the CAMetalLayer
    /// level rather than via `.clipShape` — SwiftUI's clipShape on a
    /// Metal-backed NSViewRepresentable can leave one or more edges
    /// un-clipped (users reported the top corners rounded but the right
    /// side rendered as a straight vertical line).
    private func metalPreview(cornerRadius: CGFloat) -> some View {
        MetalPreviewView(
            player: coordinator.player,
            playerItem: coordinator.playerItem,
            backgroundStyle: EditorKit.BackgroundStyle(enabled: false), // zoom only
            zoomSegments: coordinator.project.zoomSegments,
            videoSize: coordinator.project.videoSize,
            cursorTimeline: coordinator.cursorTimeline,
            cursorCIImage: coordinator.cursorCIImage,
            cursorOverlayProvider: coordinator.cursorOverlayProvider,
            cornerRadius: cornerRadius
        )
    }

    /// Renders the framed preview at a given preview→source scale.
    ///
    /// `displayScale` converts source-pixel units (slider values for
    /// cornerRadius / padding / shadowRadius) into view points. This keeps
    /// the preview visually consistent with the exported video, which is
    /// drawn in source space by `FrameCompositor`.
    private func previewWithBackground(displayScale: CGFloat) -> some View {
        let scaledCorner = frameCornerRadius * displayScale
        let scaledPadding = bg.padding * displayScale
        let scaledShadowRadius = bg.shadowRadius * displayScale

        return ZStack {
            // Flat background rectangle — no corner clipping. Matches
            // Annotate's BeautifyBackground structure exactly.
            backgroundFill

            metalPreview(cornerRadius: scaledCorner)
                .shadow(
                    color: bg.shadowEnabled
                        ? .black.opacity(bg.shadowOpacity)
                        : .clear,
                    radius: bg.shadowEnabled ? scaledShadowRadius : 0,
                    y: bg.shadowEnabled ? scaledShadowRadius * 0.3 : 0
                )
                .padding(scaledPadding)
        }
    }

    @ViewBuilder
    private var backgroundFill: some View {
        switch bg.colorType {
        case .solid:
            Color(red: bg.solidColor.red, green: bg.solidColor.green, blue: bg.solidColor.blue, opacity: bg.solidColor.alpha)
        case .gradient:
            LinearGradient(
                colors: [
                    Color(red: bg.gradientFrom.red, green: bg.gradientFrom.green, blue: bg.gradientFrom.blue),
                    Color(red: bg.gradientTo.red, green: bg.gradientTo.green, blue: bg.gradientTo.blue),
                ],
                startPoint: gradientStartPoint,
                endPoint: gradientEndPoint
            )
        case .liquidGlass:
            // Second player view blurred as backdrop — same as before, proven to work
            MetalPreviewView(
                player: coordinator.player,
                playerItem: coordinator.playerItem,
                backgroundStyle: EditorKit.BackgroundStyle(enabled: false),
                zoomSegments: [],
                videoSize: coordinator.project.videoSize,
                cursorTimeline: nil,
                cursorCIImage: nil,
                cursorOverlayProvider: nil
            )
            .scaleEffect(1.15)
            .blur(radius: 40)
            .saturation(1.8)
            .contrast(0.95)
            .allowsHitTesting(false)
        }
    }

    private var gradientStartPoint: UnitPoint {
        let angle = bg.gradientAngle
        return UnitPoint(
            x: 0.5 - cos(angle * .pi / 180) * 0.5,
            y: 0.5 - sin(angle * .pi / 180) * 0.5
        )
    }

    private var gradientEndPoint: UnitPoint {
        let angle = bg.gradientAngle
        return UnitPoint(
            x: 0.5 + cos(angle * .pi / 180) * 0.5,
            y: 0.5 + sin(angle * .pi / 180) * 0.5
        )
    }
}
