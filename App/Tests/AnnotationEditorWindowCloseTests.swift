import AppKit
import XCTest
import AnnotationKit
import SharedKit
@testable import Capso

@MainActor
final class AnnotationEditorWindowCloseTests: XCTestCase {
    private func makeTestImage(width: Int = 2, height: Int = 2) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func makeWindow(onClose: @escaping () -> Void) throws -> AnnotationEditorWindow {
        AnnotationEditorWindow(
            image: try makeTestImage(),
            screenshotOutputPreset: .losslessPNG,
            screenshotFilenameTemplate: "Screenshot",
            onSave: { _ in true },
            onCopy: { _ in },
            onPin: { _, _ in },
            onClose: onClose
        )
    }

    private func makeInlineWindow(onClose: @escaping () -> Void) throws -> InlineAnnotationEditorWindow {
        let screen = try XCTUnwrap(NSScreen.main)
        return InlineAnnotationEditorWindow(
            image: try makeTestImage(),
            screen: screen,
            screenLocalRect: CGRect(x: 0, y: 0, width: 2, height: 2),
            onSave: { _ in },
            onCopy: { _ in },
            onPin: { _, _ in },
            onClose: onClose
        )
    }

    func testRequestCloseClosesCleanEditorWithoutPrompt() throws {
        var closeCount = 0
        var confirmCount = 0
        let window = try makeWindow(onClose: { closeCount += 1 })
        window.confirmDiscard = { confirmCount += 1; return true }

        window.requestClose()

        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(confirmCount, 0)
    }

    func testRequestCloseKeepsDirtyEditorWhenDeclined() throws {
        var closeCount = 0
        let window = try makeWindow(onClose: { closeCount += 1 })
        window.document.addObject(ArrowObject(start: .zero, end: CGPoint(x: 10, y: 10)))
        window.confirmDiscard = { false }

        window.requestClose()

        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(window.document.objects.count, 1)
    }

    func testRequestCloseDiscardsWhenConfirmed() throws {
        var closeCount = 0
        let window = try makeWindow(onClose: { closeCount += 1 })
        window.document.addObject(ArrowObject(start: .zero, end: CGPoint(x: 10, y: 10)))
        window.confirmDiscard = { true }

        window.requestClose()

        XCTAssertEqual(closeCount, 1)
    }

    func testWindowShouldCloseGuardsRedTitlebarButton() throws {
        var confirmCount = 0
        let window = try makeWindow(onClose: {})
        window.document.addObject(ArrowObject(start: .zero, end: CGPoint(x: 10, y: 10)))
        window.confirmDiscard = { confirmCount += 1; return false }

        XCTAssertFalse(window.windowShouldClose(window))
        XCTAssertEqual(confirmCount, 1)

        window.document.undo()
        confirmCount = 0
        XCTAssertTrue(window.windowShouldClose(window))
        XCTAssertEqual(confirmCount, 0)
    }

    func testDirectCloseBypassesConfirmationForSaveCopyPin() throws {
        var closeCount = 0
        var confirmCount = 0
        let window = try makeWindow(onClose: { closeCount += 1 })
        window.document.addObject(ArrowObject(start: .zero, end: CGPoint(x: 10, y: 10)))
        window.confirmDiscard = { confirmCount += 1; return false }

        window.close()

        XCTAssertEqual(confirmCount, 0)
        XCTAssertEqual(closeCount, 1)
    }

    func testInlineRequestCloseTrio() throws {
        var closeCount = 0
        let cleanWindow = try makeInlineWindow(onClose: { closeCount += 1 })
        cleanWindow.confirmDiscard = { true }
        cleanWindow.requestClose()
        XCTAssertEqual(closeCount, 1)

        closeCount = 0
        let declinedWindow = try makeInlineWindow(onClose: { closeCount += 1 })
        declinedWindow.document.addObject(ArrowObject(start: .zero, end: CGPoint(x: 10, y: 10)))
        declinedWindow.confirmDiscard = { false }
        declinedWindow.requestClose()
        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(declinedWindow.document.objects.count, 1)

        closeCount = 0
        let confirmedWindow = try makeInlineWindow(onClose: { closeCount += 1 })
        confirmedWindow.document.addObject(ArrowObject(start: .zero, end: CGPoint(x: 10, y: 10)))
        confirmedWindow.confirmDiscard = { true }
        confirmedWindow.requestClose()
        XCTAssertEqual(closeCount, 1)
    }
}
