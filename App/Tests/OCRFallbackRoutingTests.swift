import Foundation
import OCRKit
import XCTest
@testable import Capso

final class OCRFallbackRoutingTests: XCTestCase {
    private static let visionFailure = NSError(
        domain: "TextRecognition.CRImageReaderError", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "TextRecognition.CRImageReaderError"]
    )

    func testConfirmedFailureSkipsPrimaryOnSubsequentCaptures() async throws {
        let router = OCRFallbackRouter()
        let calls = OCRRoutingCalls()
        for _ in 0..<3 {
            _ = try await router.recognize(automaticLanguages: true) { @Sendable in
                await calls.recordPrimary()
                throw Self.visionFailure
            } fallback: { @Sendable in
                await calls.recordFallback()
                return []
            }
        }
        let counts = await calls.counts
        XCTAssertEqual(counts.primary, 1)
        XCTAssertEqual(counts.fallback, 3)
    }

    func testSuccessfulPrimaryDoesNotLatchFallback() async throws {
        let router = OCRFallbackRouter()
        let calls = OCRRoutingCalls()
        for _ in 0..<3 {
            _ = try await router.recognize(automaticLanguages: true) { @Sendable in
                await calls.recordPrimary()
                return []
            } fallback: { @Sendable in
                await calls.recordFallback()
                return []
            }
        }
        let counts = await calls.counts
        XCTAssertEqual(counts.primary, 3)
        XCTAssertEqual(counts.fallback, 0)
    }

    func testCancelledHelperDoesNotLatchFallback() async throws {
        let router = OCRFallbackRouter()
        let task = Task { @Sendable in
            try await router.recognize(automaticLanguages: true) { @Sendable in
                throw Self.visionFailure
            } fallback: { @Sendable in
                withUnsafeCurrentTask { $0?.cancel() }
                return []
            }
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let calls = OCRRoutingCalls()
        _ = try await router.recognize(automaticLanguages: true) { @Sendable in
            await calls.recordPrimary()
            return []
        } fallback: { @Sendable in
            await calls.recordFallback()
            return []
        }
        let counts = await calls.counts
        XCTAssertEqual(counts.primary, 1)
        XCTAssertEqual(counts.fallback, 0)
    }

    func testCancellationInLatchedHelperStillPropagates() async throws {
        let router = OCRFallbackRouter()
        _ = try await router.recognize(automaticLanguages: true) { @Sendable in
            throw Self.visionFailure
        } fallback: { @Sendable in [] }
        let task = Task { @Sendable in
            try await router.recognize(automaticLanguages: true) { @Sendable in
                XCTFail("A confirmed failure must bypass the primary")
                return []
            } fallback: { @Sendable in
                withUnsafeCurrentTask { $0?.cancel() }
                return []
            }
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testFailedHelperDoesNotLatchFallback() async throws {
        let router = OCRFallbackRouter()
        do {
            _ = try await router.recognize(automaticLanguages: true) { @Sendable in
                throw Self.visionFailure
            } fallback: { @Sendable in
                throw URLError(.cannotDecodeContentData)
            }
            XCTFail("Expected helper error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cannotDecodeContentData)
        }
        let calls = OCRRoutingCalls()
        _ = try await router.recognize(automaticLanguages: true) { @Sendable in
            await calls.recordPrimary()
            return []
        } fallback: { @Sendable in
            await calls.recordFallback()
            return []
        }
        let counts = await calls.counts
        XCTAssertEqual(counts.primary, 1)
        XCTAssertEqual(counts.fallback, 0)
    }

    func testExplicitLanguagesStillUsePrimaryAfterConfirmedFailure() async throws {
        let router = OCRFallbackRouter()
        _ = try await router.recognize(automaticLanguages: true) { @Sendable in
            throw Self.visionFailure
        } fallback: { @Sendable in [] }
        let calls = OCRRoutingCalls()
        _ = try await router.recognize(automaticLanguages: false) { @Sendable in
            await calls.recordPrimary()
            return []
        } fallback: { @Sendable in
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
            _ = try await router.recognize(automaticLanguages: true) { @Sendable in
                throw URLError(.unknown)
            } fallback: { @Sendable in
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
        let task = Task { @Sendable in
            try await router.recognize(automaticLanguages: true) { @Sendable in
                withUnsafeCurrentTask { $0?.cancel() }
                throw Self.visionFailure
            } fallback: { @Sendable in
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
