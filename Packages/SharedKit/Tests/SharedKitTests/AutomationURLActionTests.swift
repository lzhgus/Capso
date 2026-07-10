import Foundation
import Testing
@testable import SharedKit

@Suite("Automation URL actions")
struct AutomationURLActionTests {
    @Test("Supported URLs map to capture actions")
    func supportedURLs() {
        let cases: [(String, AutomationURLAction)] = [
            ("capso://grab/area", .captureArea),
            ("capso://grab/fullscreen", .captureFullscreen),
            ("capso://grab/window", .captureWindow),
            ("CAPSO://GRAB/area", .captureArea),
        ]

        for (rawURL, expected) in cases {
            #expect(AutomationURLAction(url: URL(string: rawURL)!) == expected)
        }
    }

    @Test("Unsupported or parameterized URLs are rejected")
    func unsupportedURLs() {
        let urls = [
            "https://grab/area",
            "capso://capture/area",
            "capso://grab",
            "capso://grab/AREA",
            "capso://grab/ocr",
            "capso://grab//area",
            "capso://grab/area/",
            "capso://grab/%61rea",
            "capso://grab/area/extra",
            "capso://grab/area?then=save",
            "capso://grab/area#fragment",
            "capso://user@grab/area",
            "capso://grab:123/area",
        ]

        for rawURL in urls {
            #expect(AutomationURLAction(url: URL(string: rawURL)!) == nil)
        }
    }

    @Test("Request buffer retains only the first action until ready")
    func retainsFirstAction() {
        var buffer = AutomationURLRequestBuffer()
        buffer.enqueue(.captureArea)
        buffer.enqueue(.captureWindow)

        #expect(buffer.takeIfReady(
            coordinatorIsReady: false,
            captureSelectionIsActive: false
        ) == nil)
        #expect(buffer.takeIfReady(
            coordinatorIsReady: true,
            captureSelectionIsActive: false
        ) == .captureArea)
        #expect(buffer.takeIfReady(
            coordinatorIsReady: true,
            captureSelectionIsActive: false
        ) == nil)
    }

    @Test("Busy selection consumes and discards the pending action")
    func busySelectionDropsAction() {
        var buffer = AutomationURLRequestBuffer()
        buffer.enqueue(.captureFullscreen)

        #expect(buffer.takeIfReady(
            coordinatorIsReady: true,
            captureSelectionIsActive: true
        ) == nil)
        #expect(buffer.takeIfReady(
            coordinatorIsReady: true,
            captureSelectionIsActive: false
        ) == nil)
    }
}
