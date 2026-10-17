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

    func testResultResizePreservesDraggedCardTopEdge() {
        let lastProgrammaticFrame = NSRect(x: 100, y: 100, width: 420, height: 160)
        let draggedFrame = NSRect(x: 300, y: 400, width: 420, height: 160)
        let preferredFrame = NSRect(x: 120, y: 80, width: 420, height: 360)

        let resized = TranslationResultWindow.frameAfterResize(
            currentFrame: draggedFrame,
            lastProgrammaticFrame: lastProgrammaticFrame,
            preferredFrame: preferredFrame
        )

        XCTAssertEqual(resized.minX, draggedFrame.minX)
        XCTAssertEqual(resized.maxY, draggedFrame.maxY)
        XCTAssertEqual(resized.size, preferredFrame.size)
    }

    func testResultResizeUsesPreferredFrameWhenCardWasNotDragged() {
        let currentFrame = NSRect(x: 100, y: 100, width: 420, height: 160)
        let preferredFrame = NSRect(x: 120, y: 80, width: 420, height: 360)

        XCTAssertEqual(
            TranslationResultWindow.frameAfterResize(
                currentFrame: currentFrame,
                lastProgrammaticFrame: currentFrame,
                preferredFrame: preferredFrame
            ),
            preferredFrame
        )
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

final class OCRFallbackRoutingTests: XCTestCase {
    private static let visionFailure = NSError(
        domain: "TextRecognition.CRImageReaderError", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "TextRecognition.CRImageReaderError"]
    )

    func testConfirmedFailureSkipsPrimaryOnSubsequentCaptures() async throws {
        let router = OCRFallbackRouter()
        let calls = OCRRoutingCalls()
        for _ in 0..<3 {
            _ = try await router.recognize(automaticLanguages: true) {
                await calls.recordPrimary()
                throw Self.visionFailure
            } fallback: {
                await calls.recordFallback()
                return []
            }
        }
        let counts = await calls.counts
        XCTAssertEqual(counts.primary, 1)
        XCTAssertEqual(counts.fallback, 3)
    }

    func testFailedHelperDoesNotLatchFallback() async throws {
        let router = OCRFallbackRouter()
        do {
            _ = try await router.recognize(automaticLanguages: true) {
                throw Self.visionFailure
            } fallback: {
                throw URLError(.cannotDecodeContentData)
            }
            XCTFail("Expected helper error")
        } catch {}
        let calls = OCRRoutingCalls()
        _ = try await router.recognize(automaticLanguages: true) {
            await calls.recordPrimary()
            return []
        } fallback: {
            await calls.recordFallback()
            return []
        }
        let counts = await calls.counts
        XCTAssertEqual(counts.primary, 1)
        XCTAssertEqual(counts.fallback, 0)
    }

    func testExplicitLanguagesStillUsePrimaryAfterConfirmedFailure() async throws {
        let router = OCRFallbackRouter()
        _ = try await router.recognize(automaticLanguages: true) {
            throw Self.visionFailure
        } fallback: { [] }
        let calls = OCRRoutingCalls()
        _ = try await router.recognize(automaticLanguages: false) {
            await calls.recordPrimary()
            return []
        } fallback: {
            await calls.recordFallback()
            return []
        }
        let counts = await calls.counts
        XCTAssertEqual(counts.primary, 1)
        XCTAssertEqual(counts.fallback, 0)
    }

    func testUnrelatedErrorsDoNotInvokeHelper() async {
        let router = OCRFallbackRouter()
        let calls = OCRRoutingCalls()
        do {
            _ = try await router.recognize(automaticLanguages: true) {
                throw URLError(.unknown)
            } fallback: {
                await calls.recordFallback()
                return []
            }
            XCTFail("Expected original error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .unknown)
        }
        let counts = await calls.counts
        XCTAssertEqual(counts.fallback, 0)
    }

    func testCancellationDuringPrimaryDoesNotLaunchHelper() async {
        let router = OCRFallbackRouter()
        let calls = OCRRoutingCalls()
        let task = Task {
            try await router.recognize(automaticLanguages: true) {
                withUnsafeCurrentTask { $0?.cancel() }
                throw Self.visionFailure
            } fallback: {
                await calls.recordFallback()
                return []
            }
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let counts = await calls.counts
        XCTAssertEqual(counts.fallback, 0)
    }
}

private actor OCRRoutingCalls {
    private(set) var counts = (primary: 0, fallback: 0)
    func recordPrimary() { counts.primary += 1 }
    func recordFallback() { counts.fallback += 1 }
}
