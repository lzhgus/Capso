// App/Sources/AnnotationEditor/ZoomableScrollContainer.swift
import AppKit
import SwiftUI
import CaptureKit

/// A scrollable, focal-point-zoomable host for the annotator canvas.
///
/// SwiftUI's `ScrollView` can't set an arbitrary programmatic content offset,
/// which cursor-centered pinch zoom requires. This wraps an AppKit `NSScrollView`
/// so we get scrollbars / two-finger pan / momentum for free while driving the
/// scale through the shared `zoomScale` binding and holding the pinch point fixed
/// via `CanvasZoom`. Rendering stays `zoomScale`-based exactly as before.
///
/// Flow: a gesture only *reports* the desired scale + focal point and writes the
/// `zoomScale` binding. SwiftUI then re-renders the content at the new scale and
/// `updateNSView` performs the document resize + focal reposition in one pass, so
/// the document size and the rendered content never disagree mid-zoom.
struct ZoomableScrollContainer<Content: View>: NSViewRepresentable {
    @Binding var zoomScale: CGFloat
    /// Full pixel size of the content at the current `zoomScale`
    /// (i.e. the editor's `previewWidth` × `previewHeight`).
    let contentSize: CGSize
    let minScale: CGFloat
    let maxScale: CGFloat
    let content: Content

    init(
        zoomScale: Binding<CGFloat>,
        contentSize: CGSize,
        minScale: CGFloat = 0.1,
        maxScale: CGFloat = 4.0,
        @ViewBuilder content: () -> Content
    ) {
        self._zoomScale = zoomScale
        self.contentSize = contentSize
        self.minScale = minScale
        self.maxScale = maxScale
        self.content = content()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> FocalZoomScrollView {
        let scrollView = FocalZoomScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(white: 0.12, alpha: 1)
        scrollView.minScale = minScale
        scrollView.maxScale = maxScale
        scrollView.currentScale = zoomScale

        let documentView = FlippedContainerView()
        documentView.frame = CGRect(origin: .zero, size: contentSize)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = documentView.bounds
        hosting.autoresizingMask = [.width, .height]
        documentView.addSubview(hosting)
        scrollView.documentView = documentView

        context.coordinator.hostingView = hosting
        return scrollView
    }

    func updateNSView(_ scrollView: FocalZoomScrollView, context: Context) {
        context.coordinator.hostingView?.rootView = content
        scrollView.minScale = minScale
        scrollView.maxScale = maxScale

        let coordinator = context.coordinator
        // Report-only: the gesture records the focal point and writes the binding.
        scrollView.onZoomRequest = { newScale, focal in
            coordinator.pendingFocal = focal
            zoomScale = newScale
        }

        // Apply any scale change here, once SwiftUI has re-rendered `content` at
        // the new scale, so the document resize and the content match exactly.
        if abs(zoomScale - scrollView.currentScale) > 0.0001 {
            scrollView.applyScale(zoomScale, contentSize: contentSize, focal: coordinator.pendingFocal)
            coordinator.pendingFocal = nil
        } else {
            scrollView.syncDocumentSize(contentSize)
        }
    }

    @MainActor
    final class Coordinator {
        var hostingView: NSHostingView<Content>?
        /// Focal point (viewport-relative) captured from the last gesture, or nil
        /// for a button/Fit change (which recenters on the viewport center).
        var pendingFocal: CGPoint?
    }
}

/// A flipped container so the scroll view uses top-left origin coordinates,
/// matching `CanvasZoom`'s content-origin convention.
private final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}

/// Clip view that centers the document view whenever it is smaller than the
/// viewport, instead of pinning it to the top-left. Plain `NSScrollView` refuses
/// negative scroll origins, so centering a small document has to happen here.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let doc = documentView.frame.size
        if doc.width < rect.width {
            rect.origin.x = (doc.width - rect.width) / 2
        }
        if doc.height < rect.height {
            rect.origin.y = (doc.height - rect.height) / 2
        }
        return rect
    }
}

/// `NSScrollView` subclass that turns trackpad pinch and ⌘-scroll into a zoom
/// *request* (new scale + focal point). The representable applies it.
final class FocalZoomScrollView: NSScrollView {
    var currentScale: CGFloat = 1
    var minScale: CGFloat = 0.1
    var maxScale: CGFloat = 4.0
    /// Reports a desired (newScale, focalInViewport). Focal is in viewport-relative
    /// coordinates (0...viewportSize, top-left origin).
    var onZoomRequest: ((CGFloat, CGPoint) -> Void)?

    // Re-center on every layout pass. `constrainBoundsRect` alone is timing
    // dependent (it can run before the viewport has a real size and isn't
    // reliably re-invoked afterwards), which left small images pinned top-left.
    // `tile()` is called by AppKit whenever the scroll view lays out, so this is
    // the dependable hook.
    override func tile() {
        super.tile()
        recenterIfContentFits()
    }

    /// Center the document on any axis where it is smaller than the viewport.
    /// No-ops on axes where the content is larger, so it never fights panning.
    func recenterIfContentFits() {
        guard let documentView else { return }
        let doc = documentView.frame.size
        let clip = contentView.bounds.size
        guard clip.width > 0, clip.height > 0 else { return }
        var origin = contentView.bounds.origin
        if doc.width <= clip.width { origin.x = (doc.width - clip.width) / 2 }
        if doc.height <= clip.height { origin.y = (doc.height - clip.height) / 2 }
        guard origin != contentView.bounds.origin else { return }
        contentView.setBoundsOrigin(origin)
        reflectScrolledClipView(contentView)
    }

    // Trackpad pinch — `event.magnification` is a per-event delta.
    override func magnify(with event: NSEvent) {
        requestZoom(to: currentScale * (1 + event.magnification), focalInWindow: event.locationInWindow)
    }

    // ⌘-scroll (or ⌘ + precise trackpad) zooms; plain scrolling pans as usual.
    override func scrollWheel(with event: NSEvent) {
        switch CanvasScrollGesture.action(
            commandHeld: event.modifierFlags.contains(.command),
            isMomentum: event.momentumPhase != [],
            verticalDelta: event.scrollingDeltaY,
            horizontalDelta: event.scrollingDeltaX,
            hasPreciseDeltas: event.hasPreciseScrollingDeltas
        ) {
        case let .zoom(factor):
            requestZoom(to: currentScale * factor, focalInWindow: event.locationInWindow)
        case .pan:
            // Pan by moving the clip origin directly. We can't defer to
            // `super.scrollWheel`: NSScrollView's responsive scrolling ignores
            // scrollWheel events delivered programmatically (as they are when the
            // canvas hands off an over-image two-finger drag), so it would
            // silently do nothing.
            panContent(with: event)
        case .ignore:
            // A ⌘-scroll event with no usable scale change. Swallow it so one
            // zoom gesture can't also shift the canvas.
            break
        }
    }

    private func panContent(with event: NSEvent) {
        guard let documentView else { return }
        let clipView = contentView
        let doc = documentView.frame.size
        let viewport = clipView.bounds.size
        var origin = clipView.bounds.origin
        origin.x = pannedAxis(origin.x - event.scrollingDeltaX, doc: doc.width, viewport: viewport.width)
        origin.y = pannedAxis(origin.y - event.scrollingDeltaY, doc: doc.height, viewport: viewport.height)
        clipView.scroll(to: origin)
        reflectScrolledClipView(clipView)
    }

    /// Constrain a panned origin on one axis. When the content fits, hold the
    /// centered position (matching `recenterIfContentFits`) instead of clamping
    /// to 0, which would snap a centered image to the edge on the first drag.
    private func pannedAxis(_ value: CGFloat, doc: CGFloat, viewport: CGFloat) -> CGFloat {
        guard doc > viewport else { return (doc - viewport) / 2 }
        return min(max(0, value), doc - viewport)
    }

    private func requestZoom(to proposed: CGFloat, focalInWindow: NSPoint) {
        let newScale = CanvasZoom.clampScale(proposed, min: minScale, max: maxScale)
        guard newScale != currentScale else { return }
        let clipView = contentView
        // `convert(from: nil)` yields a point in the clip's bounds space, which
        // includes the scroll offset; subtract it for the viewport-relative focal.
        let inClipBounds = clipView.convert(focalInWindow, from: nil)
        let focal = CGPoint(
            x: inClipBounds.x - clipView.bounds.origin.x,
            y: inClipBounds.y - clipView.bounds.origin.y
        )
        onZoomRequest?(newScale, focal)
    }

    /// Resize the document to `contentSize` and reposition so `focal` (or the
    /// viewport center when nil) stays fixed, then record the new scale.
    func applyScale(_ newScale: CGFloat, contentSize: CGSize, focal: CGPoint?) {
        guard let documentView, currentScale > 0 else {
            syncDocumentSize(contentSize)
            currentScale = newScale
            return
        }
        let oldScale = currentScale
        let clipView = contentView
        let viewport = clipView.bounds.size
        let f = focal ?? CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let currentOffset = CGPoint(x: -clipView.bounds.origin.x, y: -clipView.bounds.origin.y)

        documentView.setFrameSize(contentSize)

        let newOffset = CanvasZoom.focalOffset(
            oldScale: oldScale,
            newScale: newScale,
            focalPoint: f,
            currentOffset: currentOffset
        )
        let clamped = CanvasZoom.clampOffset(newOffset, contentSize: contentSize, viewportSize: viewport)
        clipView.scroll(to: CGPoint(x: -clamped.x, y: -clamped.y))
        reflectScrolledClipView(clipView)

        currentScale = newScale
        recenterIfContentFits()
    }

    /// Resize the document view without disturbing the scroll position.
    func syncDocumentSize(_ size: CGSize) {
        guard let documentView, documentView.frame.size != size else { return }
        documentView.setFrameSize(size)
        recenterIfContentFits()
    }
}
