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
