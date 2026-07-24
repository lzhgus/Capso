import CoreGraphics
import Testing
@testable import CaptureKit

@Suite("Window capture candidates")
struct WindowCaptureCandidateTests {
    @Test("Includes the system menu bar without an owning application")
    func includesSystemMenuBar() {
        #expect(ContentEnumerator.isCaptureCandidate(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 30),
            isOnScreen: true,
            title: "Menubar",
            appName: "",
            hasOwningApplication: false,
            windowLayer: Int(CGWindowLevelForKey(.mainMenuWindow)),
            isOwnAppWindow: false
        ))
    }

    @Test("Includes elevated application popovers")
    func includesElevatedApplicationPopover() {
        #expect(ContentEnumerator.isCaptureCandidate(
            frame: CGRect(x: 840, y: 30, width: 240, height: 160),
            isOnScreen: true,
            title: "",
            appName: "Control Center",
            hasOwningApplication: true,
            windowLayer: 27,
            isOwnAppWindow: false
        ))
    }

    @Test("Excludes tiny ownerless status windows")
    func excludesTinyOwnerlessStatusWindow() {
        #expect(!ContentEnumerator.isCaptureCandidate(
            frame: CGRect(x: 1896, y: 1, width: 28, height: 28),
            isOnScreen: true,
            title: "StatusIndicator",
            appName: "",
            hasOwningApplication: false,
            windowLayer: Int(CGWindowLevelForKey(.cursorWindow)),
            isOwnAppWindow: false
        ))
    }
}
