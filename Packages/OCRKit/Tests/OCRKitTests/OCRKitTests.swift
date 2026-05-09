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
}
