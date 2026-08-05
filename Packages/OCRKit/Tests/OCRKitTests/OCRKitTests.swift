import XCTest
@testable import OCRKit

final class OCRKitTests: XCTestCase {
    func testOneShotContinuationIgnoresSecondResume() async throws {
        let value: String = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let oneShot = OneShotContinuation(continuation)

            XCTAssertTrue(oneShot.resume(returning: "first"))
            XCTAssertFalse(oneShot.resume(returning: "second"))
        }

        XCTAssertEqual(value, "first")
    }

    /// Prewarm must complete without throwing or crashing, even though it
    /// recognizes a blank image with no text in it.
    func testPrewarmCompletes() async {
        await TextRecognizer.prewarm()
    }
}
