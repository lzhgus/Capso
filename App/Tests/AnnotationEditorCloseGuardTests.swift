import XCTest
@testable import Capso

@MainActor
final class AnnotationEditorCloseGuardTests: XCTestCase {
    func testCleanDocumentClosesWithoutPrompt() {
        var confirmCount = 0
        let shouldClose = AnnotationEditorCloseGuard.shouldClose(
            hasUnsavedChanges: false,
            confirmDiscard: {
                confirmCount += 1
                return true
            }
        )
        XCTAssertTrue(shouldClose)
        XCTAssertEqual(confirmCount, 0)
    }

    func testDirtyDocumentClosesWhenConfirmed() {
        var confirmCount = 0
        let shouldClose = AnnotationEditorCloseGuard.shouldClose(
            hasUnsavedChanges: true,
            confirmDiscard: {
                confirmCount += 1
                return true
            }
        )
        XCTAssertTrue(shouldClose)
        XCTAssertEqual(confirmCount, 1)
    }

    func testDirtyDocumentStaysOpenWhenDeclined() {
        let shouldClose = AnnotationEditorCloseGuard.shouldClose(
            hasUnsavedChanges: true,
            confirmDiscard: { false }
        )
        XCTAssertFalse(shouldClose)
    }

    func testSystemAlertSupportsRepeatedAreaCapturesWithoutBecomingModalAgain() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .capsoCaptureDidFreezeDesktop, object: nil)
        }

        let shouldClose = AnnotationEditorCloseGuard.presentDiscardAlert(above: nil)

        XCTAssertFalse(shouldClose)
        XCTAssertNil(NSApp.modalWindow)
        XCTAssertTrue(AnnotationEditorCloseGuard.isSuspendedAlertVisibleForTesting)

        NotificationCenter.default.post(name: .capsoCaptureDidEnd, object: nil)
        XCTAssertNil(NSApp.modalWindow)
        XCTAssertTrue(AnnotationEditorCloseGuard.isModelessAlertVisibleForTesting)

        NotificationCenter.default.post(name: .capsoCaptureDidFreezeDesktop, object: nil)
        XCTAssertNil(NSApp.modalWindow)
        XCTAssertTrue(AnnotationEditorCloseGuard.isSuspendedAlertVisibleForTesting)

        NotificationCenter.default.post(name: .capsoCaptureDidEnd, object: nil)
        XCTAssertNil(NSApp.modalWindow)
        XCTAssertTrue(AnnotationEditorCloseGuard.isModelessAlertVisibleForTesting)

        AnnotationEditorCloseGuard.dismissSuspendedAlertForTesting()
        XCTAssertNil(NSApp.modalWindow)
    }
}
