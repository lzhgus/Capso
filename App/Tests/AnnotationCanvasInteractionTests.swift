import AppKit
import XCTest
@testable import Capso
import AnnotationKit

@MainActor
final class AnnotationCanvasInteractionTests: XCTestCase {
    func testShiftDragCommitsASquareRectangle() throws {
        let (view, document) = makeCanvas(tool: .rectangle)

        drag(view, from: NSPoint(x: 100, y: 400), to: NSPoint(x: 300, y: 320), modifierFlags: .shift)

        let rect = try XCTUnwrap(document.objects.first as? RectangleObject).rect
        XCTAssertEqual(rect.width, rect.height, accuracy: 0.001)
        XCTAssertEqual(rect.width, 200, accuracy: 0.001)
    }

    func testFreeDragKeepsTheRectangleUnconstrained() throws {
        let (view, document) = makeCanvas(tool: .rectangle)

        drag(view, from: NSPoint(x: 100, y: 400), to: NSPoint(x: 300, y: 320))

        let rect = try XCTUnwrap(document.objects.first as? RectangleObject).rect
        XCTAssertEqual(rect.width, 200, accuracy: 0.001)
        XCTAssertEqual(rect.height, 80, accuracy: 0.001)
    }

    func testShiftDragCommitsACircularEllipse() throws {
        let (view, document) = makeCanvas(tool: .ellipse)

        drag(view, from: NSPoint(x: 120, y: 420), to: NSPoint(x: 260, y: 380), modifierFlags: .shift)

        let rect = try XCTUnwrap(document.objects.first as? EllipseObject).rect
        XCTAssertEqual(rect.width, rect.height, accuracy: 0.001)
        XCTAssertEqual(rect.width, 140, accuracy: 0.001)
    }

    func testShiftDragSnapsANearHorizontalLineFlat() throws {
        let (view, document) = makeCanvas(tool: .line)

        drag(view, from: NSPoint(x: 100, y: 300), to: NSPoint(x: 280, y: 288), modifierFlags: .shift)

        let line = try XCTUnwrap(document.objects.first as? LineObject)
        XCTAssertEqual(line.end.y, line.start.y, accuracy: 0.001)
        // The 45° snap rotates the drag rather than projecting it, so the line
        // keeps the length the pointer implied.
        let length = hypot(line.end.x - line.start.x, line.end.y - line.start.y)
        XCTAssertEqual(length, hypot(180, 12), accuracy: 0.001)
    }

    func testTogglingShiftMidDragUpdatesThePreviewLive() throws {
        let (view, _) = makeCanvas(tool: .rectangle)

        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 100, y: 400)))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 300, y: 320)))

        // The canvas is flipped, so the mouse-down at window y 400 anchors the
        // drag at image y 200 (view height 600).
        let anchor = CGPoint(x: 100, y: 200)

        let freeEnd = try XCTUnwrap(view.previewDragEnd)
        XCTAssertNotEqual(abs(freeEnd.x - anchor.x), abs(freeEnd.y - anchor.y), accuracy: 0.001)

        view.flagsChanged(with: flagsChangedEvent(modifierFlags: .shift))
        let lockedEnd = try XCTUnwrap(view.previewDragEnd)
        XCTAssertEqual(abs(lockedEnd.x - anchor.x), abs(lockedEnd.y - anchor.y), accuracy: 0.001)

        view.flagsChanged(with: flagsChangedEvent(modifierFlags: []))
        XCTAssertEqual(try XCTUnwrap(view.previewDragEnd), freeEnd)
    }

    func testShiftDoesNotConstrainThePreviewForFreehand() throws {
        let (view, _) = makeCanvas(tool: .freehand)

        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 100, y: 400)))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 300, y: 320)))
        let free = try XCTUnwrap(view.previewDragEnd)

        view.flagsChanged(with: flagsChangedEvent(modifierFlags: .shift))
        XCTAssertEqual(try XCTUnwrap(view.previewDragEnd), free, "Freehand strokes are not constrained by Shift")
    }

    func testShiftHeldBeforeMouseDownStillConstrainsTheDrag() throws {
        let (view, document) = makeCanvas(tool: .rectangle)

        // Shift is already down when the drag starts, so no flagsChanged arrives
        // during it — the lock has to come from mouseDown's modifier flags.
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 100, y: 400), modifierFlags: .shift))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 300, y: 320), modifierFlags: .shift))

        let rect = try XCTUnwrap(document.objects.first as? RectangleObject).rect
        XCTAssertEqual(rect.width, rect.height, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func makeCanvas(tool: AnnotationTool) -> (AnnotationCanvasNSView, AnnotationDocument) {
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let document = AnnotationDocument(imageSize: frame.size)
        let view = AnnotationCanvasNSView(frame: frame)
        view.document = document
        view.currentTool = tool

        let hostWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hostWindow.contentView = view
        return (view, document)
    }

    private func drag(
        _ view: AnnotationCanvasNSView,
        from start: NSPoint,
        to end: NSPoint,
        modifierFlags: NSEvent.ModifierFlags = []
    ) {
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: start, modifierFlags: modifierFlags))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: end, modifierFlags: modifierFlags))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: end, modifierFlags: modifierFlags))
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        at location: NSPoint,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    private func flagsChangedEvent(modifierFlags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 56
        )!
    }
}
