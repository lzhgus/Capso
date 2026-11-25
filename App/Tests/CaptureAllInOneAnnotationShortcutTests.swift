import AppKit
import AnnotationKit
import CaptureKit
import XCTest

@testable import Capso

@MainActor
final class CaptureAllInOneAnnotationShortcutTests: XCTestCase {
    func testCommandShiftCCopiesTheRenderedAnnotationImage() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let frozenImage = try makeImage(size: screen.frame.size)
        let toolbar = CaptureAllInOneToolbarWindow(
            selectionRect: CGRect(x: 100, y: 100, width: 240, height: 160),
            screen: screen,
            presets: [.freeform],
            activePreset: .freeform,
            frozenImage: frozenImage
        )
        defer { toolbar.close() }

        let copied = expectation(description: "Rendered annotation image copied")
        toolbar.onCopyRendered = { _, _ in copied.fulfill() }
        toolbar.show()

        let event = try commandEvent(
            character: "c",
            keyCode: 8,
            modifiers: [.command, .shift],
            windowNumber: try XCTUnwrap(NSApp.keyWindow).windowNumber
        )
        NSApp.sendEvent(event)

        wait(for: [copied], timeout: 1)
    }

    func testCommandCFallsBackToCopyRenderedImageWhenNoAnnotationIsSelected() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let toolbar = CaptureAllInOneToolbarWindow(
            selectionRect: CGRect(x: 100, y: 100, width: 240, height: 160),
            screen: screen,
            presets: [.freeform],
            activePreset: .freeform,
            frozenImage: try makeImage(size: screen.frame.size)
        )
        defer { toolbar.close() }

        // Frozen All-in-One always has an annotation overlay, but with no
        // object selected ⌘C should fall back to copy-image-and-close (Issue #237).
        let copied = expectation(description: "Rendered annotation image copied with ⌘C fallback")
        toolbar.onCopyRendered = { _, _ in copied.fulfill() }
        toolbar.show()

        let event = try commandEvent(
            character: "c",
            keyCode: 8,
            modifiers: .command,
            windowNumber: NSApp.keyWindow?.windowNumber ?? 0
        )
        NSApp.sendEvent(event)

        wait(for: [copied], timeout: 1)
    }

    func testCommandCCopiesSelectedAnnotationObjectFromFrozenOverlay() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let overlay = CaptureAllInOneAnnotationOverlay(screen: screen)
        defer { overlay.close() }
        overlay.show(
            sourceImage: try makeImage(size: CGSize(width: 240, height: 160)),
            selectionRect: CGRect(x: 100, y: 100, width: 240, height: 160),
            avoidingFrame: nil
        )

        let document = try XCTUnwrap(overlay.annotationDocument)
        let source = RectangleObject(rect: CGRect(x: 20, y: 30, width: 80, height: 50))
        document.addObject(source)

        let event = try commandEvent(
            character: "c",
            keyCode: 8,
            modifiers: .command,
            windowNumber: NSApp.keyWindow?.windowNumber ?? 0
        )
        // Selected object → consume ⌘C as annotation clipboard (no image fallback).
        XCTAssertTrue(overlay.performAnnotationClipboardShortcut(with: event))

        let destination = AnnotationDocument(imageSize: CGSize(width: 400, height: 300))
        XCTAssertTrue(AnnotationClipboard.shared.paste(into: destination, offset: .zero))
        let pasted = try XCTUnwrap(destination.objects.first as? RectangleObject)
        XCTAssertEqual(pasted.rect, source.rect)
    }

    func testCommandCReturnsFalseFromFrozenOverlayWhenNothingIsSelected() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let overlay = CaptureAllInOneAnnotationOverlay(screen: screen)
        defer { overlay.close() }
        overlay.show(
            sourceImage: try makeImage(size: CGSize(width: 240, height: 160)),
            selectionRect: CGRect(x: 100, y: 100, width: 240, height: 160),
            avoidingFrame: nil
        )

        let event = try commandEvent(
            character: "c",
            keyCode: 8,
            modifiers: .command,
            windowNumber: NSApp.keyWindow?.windowNumber ?? 0
        )
        // No selection → do not consume; toolbar falls back to copy-image-and-close.
        XCTAssertFalse(overlay.performAnnotationClipboardShortcut(with: event))
    }

    func testCommandCStillCopiesASelectionWithoutAnAnnotationOverlay() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let toolbar = CaptureAllInOneToolbarWindow(
            selectionRect: CGRect(x: 100, y: 100, width: 240, height: 160),
            screen: screen,
            presets: [.freeform],
            activePreset: .freeform
        )
        defer { toolbar.close() }

        let copied = expectation(description: "Live selection copied")
        toolbar.onCopy = { _ in copied.fulfill() }
        toolbar.show()

        let event = try commandEvent(
            character: "c",
            keyCode: 8,
            modifiers: .command,
            windowNumber: NSApp.keyWindow?.windowNumber ?? 0
        )
        NSApp.sendEvent(event)

        wait(for: [copied], timeout: 1)
    }

    func testReturnCopiesTheRenderedAnnotationImage() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let toolbar = CaptureAllInOneToolbarWindow(
            selectionRect: CGRect(x: 100, y: 100, width: 240, height: 160),
            screen: screen,
            presets: [.freeform],
            activePreset: .freeform,
            frozenImage: try makeImage(size: screen.frame.size)
        )
        defer { toolbar.close() }

        let copied = expectation(description: "Rendered annotation image copied with Return")
        toolbar.onCopyRendered = { _, _ in copied.fulfill() }
        toolbar.show()

        let event = try commandEvent(
            character: "\r",
            keyCode: 36,
            modifiers: [],
            windowNumber: NSApp.keyWindow?.windowNumber ?? 0
        )
        NSApp.sendEvent(event)

        wait(for: [copied], timeout: 1)
    }

    func testFrozenOverlayRoutesCommandDToTheAnnotationCanvas() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let overlay = CaptureAllInOneAnnotationOverlay(screen: screen)
        defer { overlay.close() }
        overlay.show(
            sourceImage: try makeImage(size: CGSize(width: 240, height: 160)),
            selectionRect: CGRect(x: 100, y: 100, width: 240, height: 160),
            avoidingFrame: nil
        )

        let document = try XCTUnwrap(overlay.annotationDocument)
        let source = RectangleObject(rect: CGRect(x: 20, y: 30, width: 80, height: 50))
        document.addObject(source)

        let event = try commandEvent(
            character: "d",
            keyCode: 2,
            modifiers: .command,
            windowNumber: NSApp.keyWindow?.windowNumber ?? 0
        )
        XCTAssertTrue(overlay.performAnnotationClipboardShortcut(with: event))

        let duplicate = try XCTUnwrap(document.objects.last as? RectangleObject)
        XCTAssertEqual(duplicate.rect, CGRect(x: 32, y: 42, width: 80, height: 50))
        XCTAssertEqual(document.selectedObjectID, duplicate.id)

        document.undo()
        XCTAssertEqual(document.objects.count, 1)
    }

    func testReturnDoesNothingWithoutAnAnnotationOverlay() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let toolbar = CaptureAllInOneToolbarWindow(
            selectionRect: CGRect(x: 100, y: 100, width: 240, height: 160),
            screen: screen,
            presets: [.freeform],
            activePreset: .freeform
        )
        defer { toolbar.close() }

        let copied = expectation(description: "Live selection is not copied with Return")
        copied.isInverted = true
        toolbar.onCopy = { _ in copied.fulfill() }
        toolbar.show()

        let event = try commandEvent(
            character: "\r",
            keyCode: 36,
            modifiers: [],
            windowNumber: NSApp.keyWindow?.windowNumber ?? 0
        )
        NSApp.sendEvent(event)

        wait(for: [copied], timeout: 0.1)
    }

    func testEscapeWhileEditingTextInAllInOneCommitsTextWithoutCancellingCapture() throws {
        let previousTool = UserDefaults.standard.object(forKey: "annotationLastTool")
        UserDefaults.standard.set(AnnotationTool.text.rawValue, forKey: "annotationLastTool")
        defer { UserDefaults.standard.set(previousTool, forKey: "annotationLastTool") }

        let screen = try XCTUnwrap(NSScreen.main)
        let toolbar = CaptureAllInOneToolbarWindow(
            selectionRect: CGRect(x: 100, y: 100, width: 320, height: 220),
            screen: screen,
            presets: [.freeform],
            activePreset: .freeform,
            frozenImage: try makeImage(size: screen.frame.size)
        )
        defer { toolbar.close() }

        var cancelled = false
        toolbar.onCancel = { cancelled = true }
        toolbar.show()

        for window in NSApp.windows {
            window.contentView?.layoutSubtreeIfNeeded()
        }
        let canvasWindow = try XCTUnwrap(
            NSApp.windows.first { $0.contentView?.firstSubview(of: AnnotationCanvasNSView.self) != nil }
        )
        let canvas = try XCTUnwrap(canvasWindow.contentView?.firstSubview(of: AnnotationCanvasNSView.self))

        let clickPoint = NSPoint(x: 80, y: 100)
        canvas.mouseDown(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: clickPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: canvasWindow.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )))
        canvas.mouseUp(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: clickPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: canvasWindow.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )))
        XCTAssertTrue(canvas.isEditingText)

        let textView = try XCTUnwrap(canvas.firstSubview(of: NSTextView.self))
        textView.insertText("Label", replacementRange: NSRange(location: 0, length: 0))

        let escapeEvent = try commandEvent(
            character: "\u{1B}",
            keyCode: 53,
            modifiers: [],
            windowNumber: canvasWindow.windowNumber
        )
        NSApp.sendEvent(escapeEvent)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertFalse(cancelled, "Esc should commit the text edit instead of cancelling capture")
        XCTAssertFalse(canvas.isEditingText)
        XCTAssertEqual(canvas.currentTool, .text)
        XCTAssertEqual((canvas.document?.objects.first as? TextObject)?.text, "Label")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "annotationLastTool"), AnnotationTool.text.rawValue)

        // Next click immediately starts a second text box without pressing T again.
        let secondClick = NSPoint(x: 200, y: 140)
        canvas.mouseDown(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: secondClick,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: canvasWindow.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )))
        canvas.mouseUp(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: secondClick,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: canvasWindow.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertTrue(canvas.isEditingText)
        let secondTextView = try XCTUnwrap(canvas.firstSubview(of: NSTextView.self))
        secondTextView.insertText("Label 2", replacementRange: NSRange(location: 0, length: 0))

        // Outside click commits without spawning a third empty box and keeps Text active.
        let outsideClick = NSPoint(x: 40, y: 40)
        canvas.mouseDown(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: outsideClick,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: canvasWindow.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )))
        canvas.mouseUp(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: outsideClick,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: canvasWindow.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertFalse(canvas.isEditingText)
        XCTAssertEqual(canvas.currentTool, .text)
        XCTAssertEqual(canvas.document?.objects.compactMap { ($0 as? TextObject)?.text }, ["Label", "Label 2"])
    }

    func testAllInOneNextCaptureStartsWithTextToolActiveWhenLastUsed() throws {
        let previousTool = UserDefaults.standard.object(forKey: "annotationLastTool")
        UserDefaults.standard.set(AnnotationTool.arrow.rawValue, forKey: "annotationLastTool")
        defer { UserDefaults.standard.set(previousTool, forKey: "annotationLastTool") }

        let screen = try XCTUnwrap(NSScreen.main)
        let frozenImage = try makeImage(size: screen.frame.size)

        // Session 1: switch to Text via 'T', place a label, commit.
        let toolbar1 = CaptureAllInOneToolbarWindow(
            selectionRect: CGRect(x: 100, y: 100, width: 320, height: 220),
            screen: screen,
            presets: [.freeform],
            activePreset: .freeform,
            frozenImage: frozenImage
        )
        toolbar1.show()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        for window in NSApp.windows {
            window.contentView?.layoutSubtreeIfNeeded()
        }
        let canvasWindow1 = try XCTUnwrap(
            NSApp.windows.first { $0.contentView?.firstSubview(of: AnnotationCanvasNSView.self) != nil }
        )
        let canvas1 = try XCTUnwrap(canvasWindow1.contentView?.firstSubview(of: AnnotationCanvasNSView.self))
        XCTAssertEqual(canvas1.currentTool, .arrow)

        NSApp.sendEvent(try commandEvent(character: "t", keyCode: 17, modifiers: [], windowNumber: canvasWindow1.windowNumber))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(canvas1.currentTool, .text)

        let p1 = NSPoint(x: 80, y: 100)
        canvas1.mouseDown(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: p1, modifierFlags: [], timestamp: 0,
            windowNumber: canvasWindow1.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )))
        canvas1.mouseUp(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp, location: p1, modifierFlags: [], timestamp: 0,
            windowNumber: canvasWindow1.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )))
        let tv1 = try XCTUnwrap(canvas1.firstSubview(of: NSTextView.self))
        tv1.insertText("Session 1", replacementRange: NSRange(location: 0, length: 0))
        canvas1.commitTextEditingIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        toolbar1.close()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        // Session 2: next screenshot opens with Text still active, ready to click & type immediately.
        let toolbar2 = CaptureAllInOneToolbarWindow(
            selectionRect: CGRect(x: 100, y: 100, width: 320, height: 220),
            screen: screen,
            presets: [.freeform],
            activePreset: .freeform,
            frozenImage: frozenImage
        )
        defer { toolbar2.close() }
        toolbar2.show()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        for window in NSApp.windows {
            window.contentView?.layoutSubtreeIfNeeded()
        }
        let canvasWindow2 = try XCTUnwrap(
            NSApp.windows.first { $0.isVisible && $0.contentView?.firstSubview(of: AnnotationCanvasNSView.self) != nil }
        )
        let canvas2 = try XCTUnwrap(canvasWindow2.contentView?.firstSubview(of: AnnotationCanvasNSView.self))
        XCTAssertEqual(canvas2.currentTool, .text)

        canvas2.mouseDown(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: p1, modifierFlags: [], timestamp: 0,
            windowNumber: canvasWindow2.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )))
        canvas2.mouseUp(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp, location: p1, modifierFlags: [], timestamp: 0,
            windowNumber: canvasWindow2.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )))
        XCTAssertTrue(canvas2.isEditingText)
    }

    private func makeImage(size: CGSize) throws -> CGImage {
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))
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

    private func commandEvent(
        character: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        windowNumber: Int
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
