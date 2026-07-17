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
}
