import AppKit
import XCTest
@testable import Capso

final class KeyPressOverlayPermissionDecisionTests: XCTestCase {
    func testOpeningSettingsCancelsCurrentRecordingAttempt() {
        XCTAssertEqual(
            KeyPressOverlayPermissionDecision.forAlertResponse(.alertFirstButtonReturn),
            .cancelRecording
        )
    }

    func testContinueWithoutOverlayKeepsCurrentRecordingAttempt() {
        XCTAssertEqual(
            KeyPressOverlayPermissionDecision.forAlertResponse(.alertSecondButtonReturn),
            .continueWithoutOverlay
        )
    }
}
