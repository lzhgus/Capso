import CoreGraphics
import Testing
@testable import CaptureKit

@Suite("Window capture candidates")
struct WindowCaptureCandidateTests {
    @Test("Includes an unlabeled system menu bar without an owning application")
    func includesUnlabeledSystemMenuBar() {
        #expect(ContentEnumerator.isCaptureCandidate(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 30),
            isOnScreen: true,
            title: "",
            appName: "",
            appBundleIdentifier: nil,
            hasOwningApplication: false,
            windowLayer: Int(CGWindowLevelForKey(.mainMenuWindow)),
            isOwnAppWindow: false
        ))
    }

    @Test("Includes a system menu bar with an unidentified owning application")
    func includesSystemMenuBarWithPlaceholderOwner() {
        #expect(ContentEnumerator.isCaptureCandidate(
            frame: CGRect(x: 0, y: 0, width: 1728, height: 33),
            isOnScreen: true,
            title: "Menubar",
            appName: "",
            appBundleIdentifier: "",
            hasOwningApplication: true,
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
            appBundleIdentifier: "com.apple.controlcenter",
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
            appBundleIdentifier: nil,
            hasOwningApplication: false,
            windowLayer: Int(CGWindowLevelForKey(.cursorWindow)),
            isOwnAppWindow: false
        ))
    }

    @Test("Includes a normal application window")
    func includesNormalApplicationWindow() {
        #expect(ContentEnumerator.isCaptureCandidate(
            frame: CGRect(x: 120, y: 80, width: 800, height: 600),
            isOnScreen: true,
            title: "Documents",
            appName: "Finder",
            appBundleIdentifier: "com.apple.finder",
            hasOwningApplication: true,
            windowLayer: 0,
            isOwnAppWindow: false
        ))
    }

    @Test(
        "Excludes full-screen system overlay windows",
        arguments: [
            ("Dock", "com.apple.dock"),
            ("Window Manager", "com.apple.WindowManager"),
            ("Wallpaper", "com.apple.wallpaper"),
        ]
    )
    func excludesFullScreenSystemOverlay(appName: String, bundleID: String) {
        #expect(ContentEnumerator.isCaptureCandidate(
            frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            isOnScreen: true,
            title: appName,
            appName: appName,
            appBundleIdentifier: bundleID,
            hasOwningApplication: true,
            windowLayer: 20,
            isOwnAppWindow: false
        ) == false)
    }
}
