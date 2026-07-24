import AppKit
import XCTest
@testable import Capso
import AnnotationKit
import CaptureKit

/// Event-routing coverage for the annotator's zoomable surfaces: the main
/// editor's scroll container must never let a ⌘-scroll leak into a pan, and the
/// inline editor (which has no scroll view) must receive scroll events itself.
@MainActor
final class AnnotationZoomEventRoutingTests: XCTestCase {

    // MARK: - Main editor scroll container

    func testCommandScrollMomentumNeitherZoomsNorPans() throws {
        let (scrollView, _) = makeScrollView()
        var zoomRequests: [CGFloat] = []
        scrollView.onZoomRequest = { scale, _ in zoomRequests.append(scale) }
        let originBefore = scrollView.contentView.bounds.origin

        scrollView.scrollWheel(with: try scrollEvent(deltaY: 12, command: true, momentum: true))

        XCTAssertTrue(zoomRequests.isEmpty, "momentum must not zoom")
        XCTAssertEqual(scrollView.contentView.bounds.origin, originBefore, "momentum must not pan")
    }

    func testMostlyHorizontalCommandScrollNeitherZoomsNorPans() throws {
        let (scrollView, _) = makeScrollView()
        var zoomRequests: [CGFloat] = []
        scrollView.onZoomRequest = { scale, _ in zoomRequests.append(scale) }
        let originBefore = scrollView.contentView.bounds.origin

        scrollView.scrollWheel(with: try scrollEvent(deltaY: 3, deltaX: 40, command: true))

        XCTAssertTrue(zoomRequests.isEmpty)
        XCTAssertEqual(scrollView.contentView.bounds.origin, originBefore)
    }

    func testCommandScrollWithUsableDeltaRequestsZoomWithoutPanning() throws {
        let (scrollView, _) = makeScrollView()
        var zoomRequests: [CGFloat] = []
        scrollView.onZoomRequest = { scale, _ in zoomRequests.append(scale) }
        let originBefore = scrollView.contentView.bounds.origin

        scrollView.scrollWheel(with: try scrollEvent(deltaY: 12, command: true))

        XCTAssertEqual(zoomRequests.count, 1)
        XCTAssertGreaterThan(try XCTUnwrap(zoomRequests.first), scrollView.currentScale)
        XCTAssertEqual(scrollView.contentView.bounds.origin, originBefore, "zooming must not also pan")
    }

    func testPlainScrollStillPans() throws {
        let (scrollView, _) = makeScrollView()
        var zoomRequests: [CGFloat] = []
        scrollView.onZoomRequest = { scale, _ in zoomRequests.append(scale) }
        let originBefore = scrollView.contentView.bounds.origin

        scrollView.scrollWheel(with: try scrollEvent(deltaY: -40))

        XCTAssertTrue(zoomRequests.isEmpty, "a plain scroll must not zoom")
        XCTAssertNotEqual(scrollView.contentView.bounds.origin, originBefore, "a plain scroll must pan")
    }

    // MARK: - Canvas hand-off

    func testCanvasForwardsScrollToTheOwnerWhenOneIsSet() throws {
        let view = makeCanvas()
        var received: [CanvasScrollEvent] = []
        view.onScroll = { received.append($0) }

        view.scrollWheel(with: try scrollEvent(deltaY: 12, deltaX: -3, command: true))

        let scroll = try XCTUnwrap(received.first)
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(scroll.deltaY, 12, accuracy: 0.001)
        XCTAssertEqual(scroll.deltaX, -3, accuracy: 0.001)
        XCTAssertTrue(scroll.commandHeld)
        XCTAssertFalse(scroll.isMomentum)
        XCTAssertTrue(scroll.hasPreciseDeltas)
    }

    func testCanvasReportsMomentumSoOwnersCanSwallowIt() throws {
        let view = makeCanvas()
        var received: [CanvasScrollEvent] = []
        view.onScroll = { received.append($0) }

        view.scrollWheel(with: try scrollEvent(deltaY: 12, command: true, momentum: true))

        XCTAssertTrue(try XCTUnwrap(received.first).isMomentum)
    }

    func testCanvasHandsScrollToTheEnclosingScrollViewWhenNoOwnerIsSet() throws {
        let (scrollView, canvas) = makeScrollView(withCanvas: true)
        let view = try XCTUnwrap(canvas)
        XCTAssertNil(view.onScroll)
        let originBefore = scrollView.contentView.bounds.origin

        view.scrollWheel(with: try scrollEvent(deltaY: -40))

        XCTAssertNotEqual(
            scrollView.contentView.bounds.origin,
            originBefore,
            "with no owner the canvas must hand scrolling to the enclosing scroll view"
        )
    }

    // MARK: - Helpers

    /// A scroll view whose document is larger than the viewport, parked away from
    /// every edge so a stray pan in any direction moves the clip and is visible to
    /// the assertions. (Parked at the top-left, an unwanted upward pan clamps to a
    /// no-op and the test passes for the wrong reason.)
    private func makeScrollView(withCanvas: Bool = false) -> (FocalZoomScrollView, AnnotationCanvasNSView?) {
        let viewport = CGRect(x: 0, y: 0, width: 400, height: 300)
        let scrollView = FocalZoomScrollView(frame: viewport)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true

        let document = NSView(frame: CGRect(x: 0, y: 0, width: 1600, height: 1200))
        var canvas: AnnotationCanvasNSView?
        if withCanvas {
            let view = AnnotationCanvasNSView(frame: document.bounds)
            view.document = AnnotationDocument(imageSize: document.bounds.size)
            document.addSubview(view)
            canvas = view
        }
        scrollView.documentView = document
        scrollView.layoutSubtreeIfNeeded()

        let hostWindow = NSWindow(
            contentRect: viewport,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        hostWindow.contentView?.addSubview(scrollView)

        scrollView.contentView.scroll(to: CGPoint(x: 400, y: 400))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return (scrollView, canvas)
    }

    private func makeCanvas() -> AnnotationCanvasNSView {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let view = AnnotationCanvasNSView(frame: frame)
        view.document = AnnotationDocument(imageSize: frame.size)
        let hostWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hostWindow.contentView = view
        return view
    }

    /// Synthesizes a continuous (trackpad-style) scroll event. `NSEvent` has no
    /// public initializer for scroll events, so this goes through `CGEvent`.
    private func scrollEvent(
        deltaY: Int32,
        deltaX: Int32 = 0,
        command: Bool = false,
        momentum: Bool = false,
        precise: Bool = true
    ) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ))
        if command {
            cgEvent.flags = .maskCommand
        }
        cgEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
        if momentum {
            // Any non-zero momentum phase marks a post-fling glide event.
            cgEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
        }
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }
}
