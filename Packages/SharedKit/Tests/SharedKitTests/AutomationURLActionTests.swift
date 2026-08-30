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
            ("capso://grab/all-in-one", .captureAllInOne),
            ("capso://grab/scrolling", .captureScrolling),
            ("capso://grab/self-timer", .captureSelfTimer),
            ("capso://grab/last-area", .captureLastArea),
            ("capso://grab/clipboard", .captureAreaToClipboard),
            ("capso://grab/area-to-clipboard", .captureAreaToClipboard),
            ("capso://grab/share", .captureAreaAndShare),
            ("capso://grab/area-and-share", .captureAreaAndShare),
            ("capso://grab/annotate", .captureAreaAndAnnotate),
            ("capso://grab/area-and-annotate", .captureAreaAndAnnotate),
            ("capso://grab/pin", .pinFromClipboard),
            ("capso://grab/pin-from-clipboard", .pinFromClipboard),
            ("capso://grab/edit-clipboard", .editClipboardImage),
            ("capso://grab/edit-clipboard-image", .editClipboardImage),
            ("capso://grab/open-image", .openImageFile),
            ("capso://grab/open-image-file", .openImageFile),
            ("capso://grab/ocr", .captureOCR),
            ("capso://grab/text", .captureOCR),
            ("capso://grab/capture-text", .captureOCR),
            ("capso://grab/translate", .captureAndTranslate),
            ("capso://grab/capture-and-translate", .captureAndTranslate),
            ("capso://grab/translate-selection", .translateSelectedText),
            ("capso://grab/translate-selected-text", .translateSelectedText),
            ("capso://grab/translate-text", .translateTypedText),
            ("capso://grab/translate-typed-text", .translateTypedText),
            ("capso://grab/record", .recordArea),
            ("capso://grab/record-area", .recordArea),
            ("capso://grab/record-screen", .recordArea),
            ("capso://grab/record-fullscreen", .recordFullscreen),
            ("capso://grab/record-full-screen", .recordFullscreen),
            ("capso://grab/history", .openHistory),
            ("capso://grab/screenshot-history", .openHistory),
            ("capso://grab/preferences", .openPreferences),
            ("capso://grab/settings", .openPreferences),
            ("CAPSO://GRAB/area", .captureArea),
            ("CAPSO://GRAB/ocr", .captureOCR),
            ("CAPSO://GRAB/record", .recordArea),
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
            "capso://grab/RECORD",
            "capso://grab/unknown",
            "capso://grab/nonexistent",
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
