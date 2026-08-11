import AnnotationKit
import AppKit
import SharedKit
import XCTest

@testable import Capso

@MainActor
final class AnnotationCanvasClipboardShortcutTests: XCTestCase {
    func testCommandCopyPasteAndDuplicateUseTheSharedAnnotationClipboard() throws {
        let clipboard = AnnotationClipboard()

        let sourceDocument = AnnotationDocument(imageSize: CGSize(width: 400, height: 300))
        let source = RectangleObject(rect: CGRect(x: 20, y: 30, width: 80, height: 50))
        sourceDocument.addObject(source)

        let sourceCanvas = AnnotationCanvasNSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        sourceCanvas.document = sourceDocument
        sourceCanvas.annotationClipboard = clipboard
        sourceCanvas.keyDown(with: try commandEvent(character: "c", keyCode: 8))

        let destinationDocument = AnnotationDocument(imageSize: CGSize(width: 400, height: 300))
        let destinationCanvas = AnnotationCanvasNSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        destinationCanvas.document = destinationDocument
        destinationCanvas.annotationClipboard = clipboard
        destinationCanvas.zoomScale = 2

        destinationCanvas.keyDown(with: try commandEvent(character: "v", keyCode: 9))
        let pasted = try XCTUnwrap(destinationDocument.objects.first as? RectangleObject)
        XCTAssertEqual(pasted.rect, CGRect(x: 26, y: 36, width: 80, height: 50))

        destinationCanvas.keyDown(with: try commandEvent(character: "d", keyCode: 2))
        let duplicate = try XCTUnwrap(destinationDocument.objects.last as? RectangleObject)
        XCTAssertEqual(duplicate.rect, CGRect(x: 32, y: 42, width: 80, height: 50))
        XCTAssertEqual(destinationDocument.selectedObjectID, duplicate.id)
    }

    func testCommandCReturnsFalseWhenNothingIsSelected() throws {
        let document = AnnotationDocument(imageSize: CGSize(width: 400, height: 300))
        let canvas = AnnotationCanvasNSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        canvas.document = document
        canvas.annotationClipboard = AnnotationClipboard()

        let event = try commandEvent(character: "c", keyCode: 8)
        XCTAssertFalse(canvas.performAnnotationClipboardShortcut(with: event))
    }

    func testCommandCReturnsTrueWhenSelectionIsCopied() throws {
        let document = AnnotationDocument(imageSize: CGSize(width: 400, height: 300))
        document.addObject(RectangleObject(rect: CGRect(x: 20, y: 30, width: 80, height: 50)))
        let canvas = AnnotationCanvasNSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        canvas.document = document
        canvas.annotationClipboard = AnnotationClipboard()

        let event = try commandEvent(character: "c", keyCode: 8)
        XCTAssertTrue(canvas.performAnnotationClipboardShortcut(with: event))
    }

    func testFullEditorDispatchesCommandCToTheCanvasSelection() throws {
        let clipboard = AnnotationClipboard()
        var copiedRenderedImage = false
        let window = AnnotationEditorWindow(
            image: try makeImage(),
            screenshotOutput: ScreenshotOutputOptions(format: .png, quality: 0.85),
            screenshotFilenameTemplate: "Screenshot",
            onSave: { _ in true },
            onCopy: { _ in copiedRenderedImage = true },
            onPin: { _, _ in },
            onClose: {}
        )
        defer { window.close() }

        let source = RectangleObject(rect: CGRect(x: 20, y: 30, width: 80, height: 50))
        window.document.addObject(source)
        window.show()
        window.contentView?.layoutSubtreeIfNeeded()

        let canvas = try XCTUnwrap(firstSubview(of: AnnotationCanvasNSView.self, in: window.contentView))
        canvas.annotationClipboard = clipboard
        let focusView = ShortcutFocusView()
        window.contentView?.addSubview(focusView)
        XCTAssertTrue(window.makeFirstResponder(focusView))

        let event = try commandEvent(character: "c", keyCode: 8, windowNumber: window.windowNumber)
        window.sendEvent(event)

        XCTAssertFalse(copiedRenderedImage)
        let destination = AnnotationDocument(imageSize: CGSize(width: 400, height: 300))
        XCTAssertTrue(clipboard.paste(into: destination, offset: .zero))
        let pasted = try XCTUnwrap(destination.objects.first as? RectangleObject)
        XCTAssertEqual(pasted.rect, source.rect)
    }

    func testInlineEditorDispatchesCommandCToTheCanvasSelection() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let clipboard = AnnotationClipboard()
        var copiedRenderedImage = false
        let window = InlineAnnotationEditorWindow(
            image: try makeImage(),
            screen: screen,
            screenLocalRect: CGRect(x: 100, y: 100, width: 400, height: 300),
            onSave: { _ in },
            onCopy: { _ in copiedRenderedImage = true },
            onPin: { _, _ in },
            onClose: {}
        )
        defer { window.close() }

        let source = RectangleObject(rect: CGRect(x: 20, y: 30, width: 80, height: 50))
        window.document.addObject(source)
        window.show()
        window.contentView?.layoutSubtreeIfNeeded()

        let canvas = try XCTUnwrap(firstSubview(of: AnnotationCanvasNSView.self, in: window.contentView))
        canvas.annotationClipboard = clipboard
        let focusView = ShortcutFocusView()
        window.contentView?.addSubview(focusView)
        XCTAssertTrue(window.makeFirstResponder(focusView))

        let event = try commandEvent(character: "c", keyCode: 8, windowNumber: window.windowNumber)
        window.sendEvent(event)

        XCTAssertFalse(copiedRenderedImage)
        let destination = AnnotationDocument(imageSize: CGSize(width: 400, height: 300))
        XCTAssertTrue(clipboard.paste(into: destination, offset: .zero))
        let pasted = try XCTUnwrap(destination.objects.first as? RectangleObject)
        XCTAssertEqual(pasted.rect, source.rect)
    }

    /// Issue #236: with no annotation object selected, ⌘C in the full editor
    /// must fall back to copy-image-and-close instead of doing nothing.
    func testFullEditorCommandCFallsBackToCopyRenderedImageWhenNothingIsSelected() throws {
        let copied = expectation(description: "Full editor image copied with ⌘C")
        let window = AnnotationEditorWindow(
            image: try makeImage(),
            screenshotOutput: ScreenshotOutputOptions(format: .png, quality: 0.85),
            screenshotFilenameTemplate: "Screenshot",
            onSave: { _ in true },
            onCopy: { _ in copied.fulfill() },
            onPin: { _, _ in },
            onClose: {}
        )
        defer { window.close() }

        window.show()
        window.contentView?.layoutSubtreeIfNeeded()
        window.sendEvent(try commandEvent(character: "c", keyCode: 8, windowNumber: window.windowNumber))

        wait(for: [copied], timeout: 1)
    }

    func testInlineEditorCommandCFallsBackToCopyRenderedImageWhenNothingIsSelected() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let copied = expectation(description: "Inline editor image copied with ⌘C")
        let window = InlineAnnotationEditorWindow(
            image: try makeImage(),
            screen: screen,
            screenLocalRect: CGRect(x: 100, y: 100, width: 400, height: 300),
            onSave: { _ in },
            onCopy: { _ in copied.fulfill() },
            onPin: { _, _ in },
            onClose: {}
        )
        defer { window.close() }

        window.show()
        window.contentView?.layoutSubtreeIfNeeded()
        window.sendEvent(try commandEvent(character: "c", keyCode: 8, windowNumber: window.windowNumber))

        wait(for: [copied], timeout: 1)
    }

    /// ⌘C must not copy-and-close out from under a focused text responder —
    /// the keystroke belongs to the text being edited.
    func testFullEditorCommandCDoesNotCopyTheImageWhileATextResponderHasFocus() throws {
        let copied = expectation(description: "Image must not be copied while editing text")
        copied.isInverted = true
        let window = AnnotationEditorWindow(
            image: try makeImage(),
            screenshotOutput: ScreenshotOutputOptions(format: .png, quality: 0.85),
            screenshotFilenameTemplate: "Screenshot",
            onSave: { _ in true },
            onCopy: { _ in copied.fulfill() },
            onPin: { _, _ in },
            onClose: {}
        )
        defer { window.close() }

        window.show()
        window.contentView?.layoutSubtreeIfNeeded()

        let textView = NSTextView()
        window.contentView?.addSubview(textView)
        XCTAssertTrue(window.makeFirstResponder(textView))

        window.sendEvent(try commandEvent(character: "c", keyCode: 8, windowNumber: window.windowNumber))

        wait(for: [copied], timeout: 0.5)
    }

    func testFullEditorReturnCopiesTheRenderedImage() throws {
        let copied = expectation(description: "Full editor image copied with Return")
        let window = AnnotationEditorWindow(
            image: try makeImage(),
            screenshotOutput: ScreenshotOutputOptions(format: .png, quality: 0.85),
            screenshotFilenameTemplate: "Screenshot",
            onSave: { _ in true },
            onCopy: { _ in copied.fulfill() },
            onPin: { _, _ in },
            onClose: {}
        )
        defer { window.close() }

        window.show()
        window.contentView?.layoutSubtreeIfNeeded()
        window.sendEvent(try returnEvent(windowNumber: window.windowNumber))

        wait(for: [copied], timeout: 1)
    }

    func testInlineEditorReturnCopiesTheRenderedImage() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let copied = expectation(description: "Inline editor image copied with Return")
        let window = InlineAnnotationEditorWindow(
            image: try makeImage(),
            screen: screen,
            screenLocalRect: CGRect(x: 100, y: 100, width: 400, height: 300),
            onSave: { _ in },
            onCopy: { _ in copied.fulfill() },
            onPin: { _, _ in },
            onClose: {}
        )
        defer { window.close() }

        window.show()
        window.contentView?.layoutSubtreeIfNeeded()
        window.sendEvent(try returnEvent(windowNumber: window.windowNumber))

        wait(for: [copied], timeout: 1)
    }

    func testTextResponderKeepsNativeCommandCopyInsteadOfCopyingAnAnnotation() throws {
        let clipboard = AnnotationClipboard()
        let clipboardDocument = AnnotationDocument(imageSize: CGSize(width: 400, height: 300))
        let clipboardSource = RectangleObject(rect: CGRect(x: 10, y: 20, width: 30, height: 40))
        clipboardDocument.addObject(clipboardSource)
        XCTAssertTrue(clipboard.copySelection(from: clipboardDocument))

        let window = AnnotationEditorWindow(
            image: try makeImage(),
            screenshotOutput: ScreenshotOutputOptions(format: .png, quality: 0.85),
            screenshotFilenameTemplate: "Screenshot",
            onSave: { _ in true },
            onCopy: { _ in },
            onPin: { _, _ in },
            onClose: {}
        )
        defer { window.close() }

        window.document.addObject(RectangleObject(rect: CGRect(x: 100, y: 120, width: 60, height: 50)))
        window.show()
        window.contentView?.layoutSubtreeIfNeeded()

        let canvas = try XCTUnwrap(firstSubview(of: AnnotationCanvasNSView.self, in: window.contentView))
        canvas.annotationClipboard = clipboard
        let textView = NSTextView()
        window.contentView?.addSubview(textView)
        XCTAssertTrue(window.makeFirstResponder(textView))

        let event = try commandEvent(character: "c", keyCode: 8, windowNumber: window.windowNumber)
        XCTAssertFalse(window.routeAnnotationClipboardShortcutToCanvas(event))

        let destination = AnnotationDocument(imageSize: CGSize(width: 400, height: 300))
        XCTAssertTrue(clipboard.paste(into: destination, offset: .zero))
        let pasted = try XCTUnwrap(destination.objects.first as? RectangleObject)
        XCTAssertEqual(pasted.rect, clipboardSource.rect)
    }

    private func makeImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 400,
            height: 300,
            bitsPerComponent: 8,
            bytesPerRow: 400 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    private func firstSubview<T: NSView>(of type: T.Type, in root: NSView?) -> T? {
        guard let root else { return nil }
        if let match = root as? T { return match }
        for subview in root.subviews {
            if let match = firstSubview(of: type, in: subview) {
                return match
            }
        }
        return nil
    }

    private func commandEvent(character: String, keyCode: UInt16, windowNumber: Int = 0) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func returnEvent(windowNumber: Int) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
    }
}

@MainActor
private final class ShortcutFocusView: NSView {
    override var acceptsFirstResponder: Bool { true }
}
