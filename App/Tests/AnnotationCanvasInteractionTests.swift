import AppKit
import SharedKit
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

    func testShiftPlusCCommitsARectangleCenteredOnClick() throws {
        let (view, document) = makeCanvas(tool: .rectangle)

        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 100, y: 400), modifierFlags: .shift))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 300, y: 320), modifierFlags: .shift))
        view.handleCenterLockKeyEvent(keyEvent(keyCode: 8, characters: "c", modifierFlags: .shift))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 300, y: 320), modifierFlags: .shift))

        let rect = try XCTUnwrap(document.objects.first as? RectangleObject).rect
        XCTAssertEqual(rect.origin.x, -100, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 400, accuracy: 0.001)
        XCTAssertEqual(rect.height, 400, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 100, accuracy: 0.001)
        XCTAssertEqual(rect.midY, 200, accuracy: 0.001)
    }

    func testShiftPlusCCommitsACircularEllipseCenteredOnClick() throws {
        let (view, document) = makeCanvas(tool: .ellipse)

        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 120, y: 420), modifierFlags: .shift))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 260, y: 380), modifierFlags: .shift))
        view.handleCenterLockKeyEvent(keyEvent(keyCode: 8, characters: "c", modifierFlags: .shift))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 260, y: 380), modifierFlags: .shift))

        let rect = try XCTUnwrap(document.objects.first as? EllipseObject).rect
        XCTAssertEqual(rect.width, rect.height, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 120, accuracy: 0.001)
        XCTAssertEqual(rect.midY, 180, accuracy: 0.001)
    }

    func testShiftPlusCCommitsALineCenteredOnClick() throws {
        let (view, document) = makeCanvas(tool: .line)

        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 100, y: 300), modifierFlags: .shift))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 280, y: 288), modifierFlags: .shift))
        view.handleCenterLockKeyEvent(keyEvent(keyCode: 8, characters: "c", modifierFlags: .shift))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 280, y: 288), modifierFlags: .shift))

        let line = try XCTUnwrap(document.objects.first as? LineObject)
        let click = CGPoint(x: 100, y: 300)
        XCTAssertEqual((line.start.x + line.end.x) / 2, click.x, accuracy: 0.001)
        XCTAssertEqual((line.start.y + line.end.y) / 2, click.y, accuracy: 0.001)
        XCTAssertEqual(line.end.y, line.start.y, accuracy: 0.001)
    }

    func testTogglingCMidDragRecentersThePreviewLive() throws {
        let (view, _) = makeCanvas(tool: .rectangle)

        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 100, y: 400)))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 300, y: 320)))
        view.flagsChanged(with: flagsChangedEvent(modifierFlags: .shift))

        let cornerStart = try XCTUnwrap(view.previewDragStart)
        XCTAssertEqual(cornerStart.x, 100, accuracy: 0.001)
        XCTAssertEqual(cornerStart.y, 200, accuracy: 0.001)

        view.handleCenterLockKeyEvent(keyEvent(keyCode: 8, characters: "c", modifierFlags: .shift))
        let centeredStart = try XCTUnwrap(view.previewDragStart)
        let centeredEnd = try XCTUnwrap(view.previewDragEnd)
        XCTAssertEqual((centeredStart.x + centeredEnd.x) / 2, 100, accuracy: 0.001)
        XCTAssertEqual((centeredStart.y + centeredEnd.y) / 2, 200, accuracy: 0.001)

        view.handleCenterLockKeyEvent(keyEvent(type: .keyUp, keyCode: 8, characters: "c", modifierFlags: .shift))
        let restored = try XCTUnwrap(view.previewDragStart)
        XCTAssertEqual(restored.x, cornerStart.x, accuracy: 0.001)
        XCTAssertEqual(restored.y, cornerStart.y, accuracy: 0.001)
    }

    func testShiftPlusCDoesNotConstrainFreehand() throws {
        let (view, _) = makeCanvas(tool: .freehand)

        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 100, y: 400)))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 300, y: 320)))
        let free = try XCTUnwrap(view.previewDragEnd)

        view.flagsChanged(with: flagsChangedEvent(modifierFlags: .shift))
        view.handleCenterLockKeyEvent(keyEvent(keyCode: 8, characters: "c", modifierFlags: .shift))
        XCTAssertEqual(try XCTUnwrap(view.previewDragEnd), free)
    }

    func testAllDrawingToolsIncludingTextAreSticky() {
        for tool in AnnotationTool.allCases where tool != .select {
            XCTAssertTrue(
                AnnotationCanvasView.stickyTools.contains(tool),
                "Expected \(tool) to stay active after creating an annotation"
            )
        }
    }

    func testTextToolStaysActiveAcrossMultipleTextAnnotations() throws {
        let (view, document) = makeCanvas(tool: .text)
        var switchedToSelect = false
        view.onObjectCreated = {
            if !AnnotationCanvasView.stickyTools.contains(view.currentTool) {
                switchedToSelect = true
                view.currentTool = .select
            }
        }

        // First click opens inline text editor.
        click(view, at: NSPoint(x: 120, y: 460))
        XCTAssertTrue(view.isEditingText)
        let firstTextView = try XCTUnwrap(view.firstSubview(of: NSTextView.self))
        firstTextView.insertText("First", replacementRange: NSRange(location: 0, length: 0))

        // Clicking outside commits the first label without spawning an empty box
        // on the same click and keeps the Text tool active.
        click(view, at: NSPoint(x: 420, y: 260))
        XCTAssertFalse(view.isEditingText)
        XCTAssertFalse(switchedToSelect)
        XCTAssertEqual(view.currentTool, .text)
        XCTAssertEqual(document.objects.count, 1)
        let firstObject = try XCTUnwrap(document.objects.first as? TextObject)
        XCTAssertEqual(firstObject.text, "First")
        XCTAssertEqual(document.selectedObjectID, firstObject.id)

        // Next click immediately opens a new text box without re-selecting the tool,
        // and clears the prior selection so toolbar edits don't mutate the first box.
        click(view, at: NSPoint(x: 420, y: 260))
        XCTAssertTrue(view.isEditingText)
        XCTAssertNil(document.selectedObjectID)
        let secondTextView = try XCTUnwrap(view.firstSubview(of: NSTextView.self))
        secondTextView.insertText("Second", replacementRange: NSRange(location: 0, length: 0))

        view.commitTextEditingIfNeeded()
        XCTAssertFalse(view.isEditingText)
        XCTAssertFalse(switchedToSelect)
        XCTAssertEqual(view.currentTool, .text)
        XCTAssertEqual(document.objects.count, 2)
        XCTAssertEqual((document.objects.last as? TextObject)?.text, "Second")
    }

    func testOutsideClickWhileReeditingInSelectModeFallsThroughToSelectAnotherObject() throws {
        let (view, document) = makeCanvas(tool: .select)
        let text = TextObject(text: "Hello", origin: CGPoint(x: 100, y: 120), boxSize: CGSize(width: 140, height: 50))
        let rect = RectangleObject(
            rect: CGRect(x: 360, y: 300, width: 120, height: 80),
            style: StrokeStyle(filled: true)
        )
        document.addObject(text)
        document.addObject(rect)
        document.clearSelection()

        // Double-click text in flipped canvas coordinates (view height = 600 -> window y = 600 - imageY).
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 140, y: 460), clickCount: 2))
        XCTAssertTrue(view.isEditingText)

        // Click on the rectangle outside the text editor -> commits text AND selects rectangle.
        click(view, at: NSPoint(x: 420, y: 260))
        XCTAssertFalse(view.isEditingText)
        XCTAssertEqual(document.selectedObjectID, rect.id)
    }

    func testFullEditorKeepsTextToolActiveAcrossMultipleLabelsAndNextSession() throws {
        let previousTool = UserDefaults.standard.object(forKey: "annotationLastTool")
        UserDefaults.standard.set(AnnotationTool.arrow.rawValue, forKey: "annotationLastTool")
        defer { UserDefaults.standard.set(previousTool, forKey: "annotationLastTool") }

        let image = try makeImage(width: 600, height: 400)
        let window1 = AnnotationEditorWindow(
            image: image,
            screenshotOutput: ScreenshotOutputOptions(format: .png, quality: 0.85),
            screenshotFilenameTemplate: "Screenshot",
            onSave: { _ in true },
            onCopy: { _ in },
            onPin: { _, _ in },
            onClose: {}
        )
        defer { window1.close() }

        window1.show()
        pumpRunLoop()
        window1.contentView?.layoutSubtreeIfNeeded()
        let canvas1 = try XCTUnwrap(window1.contentView?.firstSubview(of: AnnotationCanvasNSView.self))
        XCTAssertEqual(canvas1.currentTool, .arrow)

        // Press 'T' shortcut through the live AnnotationToolShortcutMonitor.
        NSApp.sendEvent(keyEvent(keyCode: 17, characters: "t", modifierFlags: [], windowNumber: window1.windowNumber))
        pumpRunLoop()
        XCTAssertEqual(canvas1.currentTool, .text)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "annotationLastTool"), AnnotationTool.text.rawValue)

        // Place first text label and commit by clicking outside on the canvas.
        let point1 = canvas1.convert(NSPoint(x: 80, y: 80), to: nil)
        let point2 = canvas1.convert(NSPoint(x: 320, y: 220), to: nil)
        click(canvas1, at: point1, windowNumber: window1.windowNumber)
        pumpRunLoop()
        XCTAssertTrue(canvas1.isEditingText)
        let textView1 = try XCTUnwrap(canvas1.firstSubview(of: NSTextView.self))
        textView1.insertText("First Label", replacementRange: NSRange(location: 0, length: 0))

        click(canvas1, at: point2, windowNumber: window1.windowNumber)
        pumpRunLoop()
        XCTAssertFalse(canvas1.isEditingText, "Outside click should commit without spawning an empty box")
        XCTAssertEqual(canvas1.currentTool, .text, "Text tool must remain active after committing")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "annotationLastTool"), AnnotationTool.text.rawValue)
        XCTAssertEqual((window1.document.objects.first as? TextObject)?.text, "First Label")

        // Immediately place a second label WITHOUT pressing T again.
        click(canvas1, at: point2, windowNumber: window1.windowNumber)
        pumpRunLoop()
        XCTAssertTrue(canvas1.isEditingText)
        XCTAssertNil(window1.document.selectedObjectID)
        let textView2 = try XCTUnwrap(canvas1.firstSubview(of: NSTextView.self))
        textView2.insertText("Second Label", replacementRange: NSRange(location: 0, length: 0))

        // Commit via Esc — Text tool should still stay active.
        let escEvent = keyEvent(keyCode: 53, characters: "\u{1B}", modifierFlags: [], windowNumber: window1.windowNumber)
        if !window1.performKeyEquivalent(with: escEvent) {
            textView2.keyDown(with: escEvent)
        }
        pumpRunLoop()
        XCTAssertFalse(canvas1.isEditingText)
        XCTAssertEqual(canvas1.currentTool, .text)
        XCTAssertEqual(window1.document.objects.compactMap { ($0 as? TextObject)?.text }, ["First Label", "Second Label"])
        XCTAssertEqual(UserDefaults.standard.string(forKey: "annotationLastTool"), AnnotationTool.text.rawValue)

        // Open a second editor session: Text tool must still be active on reopen.
        let window2 = AnnotationEditorWindow(
            image: image,
            screenshotOutput: ScreenshotOutputOptions(format: .png, quality: 0.85),
            screenshotFilenameTemplate: "Screenshot",
            onSave: { _ in true },
            onCopy: { _ in },
            onPin: { _, _ in },
            onClose: {}
        )
        defer { window2.close() }

        window2.show()
        pumpRunLoop()
        window2.contentView?.layoutSubtreeIfNeeded()
        let canvas2 = try XCTUnwrap(window2.contentView?.firstSubview(of: AnnotationCanvasNSView.self))
        XCTAssertEqual(canvas2.currentTool, .text)

        let point3 = canvas2.convert(NSPoint(x: 120, y: 120), to: nil)
        click(canvas2, at: point3, windowNumber: window2.windowNumber)
        pumpRunLoop()
        XCTAssertTrue(canvas2.isEditingText, "Clicking directly in a new session should start text editing without re-selecting T")
    }

    func testInlineEditorKeepsTextToolActiveAcrossMultipleLabels() throws {
        let previousTool = UserDefaults.standard.object(forKey: "annotationLastTool")
        UserDefaults.standard.set(AnnotationTool.text.rawValue, forKey: "annotationLastTool")
        defer { UserDefaults.standard.set(previousTool, forKey: "annotationLastTool") }

        let screen = try XCTUnwrap(NSScreen.main)
        let window = InlineAnnotationEditorWindow(
            image: try makeImage(width: 400, height: 300),
            screen: screen,
            screenLocalRect: CGRect(x: 100, y: 100, width: 400, height: 300),
            onSave: { _ in },
            onCopy: { _ in },
            onPin: { _, _ in },
            onClose: {}
        )
        defer { window.close() }

        window.show()
        pumpRunLoop()
        window.contentView?.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(window.contentView?.firstSubview(of: AnnotationCanvasNSView.self))
        XCTAssertEqual(canvas.currentTool, .text)

        let point1 = canvas.convert(NSPoint(x: 60, y: 60), to: nil)
        let point2 = canvas.convert(NSPoint(x: 240, y: 180), to: nil)

        click(canvas, at: point1, windowNumber: window.windowNumber)
        pumpRunLoop()
        XCTAssertTrue(canvas.isEditingText)
        let tv1 = try XCTUnwrap(canvas.firstSubview(of: NSTextView.self))
        tv1.insertText("Inline 1", replacementRange: NSRange(location: 0, length: 0))

        click(canvas, at: point2, windowNumber: window.windowNumber)
        pumpRunLoop()
        XCTAssertFalse(canvas.isEditingText)
        XCTAssertEqual(canvas.currentTool, .text)

        click(canvas, at: point2, windowNumber: window.windowNumber)
        pumpRunLoop()
        XCTAssertTrue(canvas.isEditingText)
        let tv2 = try XCTUnwrap(canvas.firstSubview(of: NSTextView.self))
        tv2.insertText("Inline 2", replacementRange: NSRange(location: 0, length: 0))

        canvas.commitTextEditingIfNeeded()
        pumpRunLoop()
        XCTAssertEqual(canvas.currentTool, .text)
        XCTAssertEqual(window.document.objects.compactMap { ($0 as? TextObject)?.text }, ["Inline 1", "Inline 2"])
    }

    // MARK: - Helpers

    private func pumpRunLoop(_ duration: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

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

    private func click(
        _ view: AnnotationCanvasNSView,
        at point: NSPoint,
        modifierFlags: NSEvent.ModifierFlags = [],
        clickCount: Int = 1,
        windowNumber: Int = 0
    ) {
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: point, modifierFlags: modifierFlags, clickCount: clickCount, windowNumber: windowNumber))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: point, modifierFlags: modifierFlags, clickCount: clickCount, windowNumber: windowNumber))
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
        modifierFlags: NSEvent.ModifierFlags = [],
        clickCount: Int = 1,
        windowNumber: Int = 0
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
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

    private func keyEvent(
        type: NSEvent.EventType = .keyDown,
        keyCode: UInt16,
        characters: String,
        modifierFlags: NSEvent.ModifierFlags,
        windowNumber: Int = 0
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
