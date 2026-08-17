import Foundation
import OCRKit
import SharedKit
import TranslationKit
import XCTest
@testable import Capso

@MainActor
final class TranslationResultUXTests: XCTestCase {
    func testCancelledProviderRequestDoesNotProduceVisibleFailure() {
        XCTAssertNil(TranslationResultView.visibleFailureMessage(for: CancellationError()))
        XCTAssertNil(TranslationResultView.visibleFailureMessage(for: URLError(.cancelled)))
    }

    func testNonCancellationErrorProducesVisibleFailure() {
        let error = URLError(.notConnectedToInternet)

        XCTAssertEqual(
            TranslationResultView.visibleFailureMessage(for: error),
            error.localizedDescription
        )
    }

    func testShortTranslationUsesCompactCardHeight() {
        XCTAssertLessThan(TranslationResultWindow.preferredHeight(for: "Hello"), 400)
    }

    func testLongTranslationCapsAtScrollableCardHeight() {
        let longText = String(repeating: "A sentence that needs translation. ", count: 100)

        XCTAssertEqual(TranslationResultWindow.preferredHeight(for: longText), 520)
    }

    func testRecognizingFeedbackAppearsBeforeTranslationResult() {
        let window = makeWindow(autoDismissDelay: 1)
        defer { window.close() }

        window.showRecognizing()

        XCTAssertTrue(window.isVisible)
        XCTAssertNotNil(window.contentView)
        XCTAssertLessThan(window.frame.height, 400)
    }

    func testAutoDismissWaitsUntilTranslationCompletes() {
        let window = makeWindow(autoDismissDelay: 0.05)
        defer { window.close() }
        var didRequestClose = false
        window.onClose = { didRequestClose = true }
        window.showRecognizing()

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertFalse(didRequestClose)

        window.translationDidComplete()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertTrue(didRequestClose)
    }

    func testPinCancelsPendingAutoDismiss() {
        let window = makeWindow(autoDismissDelay: 0.05)
        defer { window.close() }
        var didRequestClose = false
        window.onClose = { didRequestClose = true }
        window.translationDidComplete()

        window.setPinned(true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertFalse(didRequestClose)
    }

    func testStartingNewTranslationInvalidatesPreviousRequest() {
        var generation = TranslationRequestGeneration()
        let first = generation.begin()
        let second = generation.begin()

        XCTAssertFalse(generation.isCurrent(first))
        XCTAssertTrue(generation.isCurrent(second))

        generation.invalidate()

        XCTAssertFalse(generation.isCurrent(second))
    }

    private func makeWindow(autoDismissDelay: TimeInterval) -> TranslationResultWindow {
        let suiteName = "TranslationResultUXTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        settings.translationAutoDismiss = .afterDelay
        settings.translationAutoDismissDelay = autoDismissDelay

        return TranslationResultWindow(
            settings: settings,
            anchor: nil,
            anchorScreen: NSScreen.main
        )
    }
}
