import Foundation
import Testing
@testable import SharedKit

@Suite("PermissionKind")
struct PermissionKindTests {
    @Test("System Settings URLs point at the expected privacy panes")
    func systemSettingsURLs() {
        #expect(PermissionKind.screenRecording.settingsURL.absoluteString.contains("Privacy_ScreenCapture"))
        #expect(PermissionKind.accessibility.settingsURL.absoluteString.contains("Privacy_Accessibility"))
        #expect(PermissionKind.inputMonitoring.settingsURL.absoluteString.contains("Privacy_ListenEvent"))
        #expect(PermissionKind.camera.settingsURL.absoluteString.contains("Privacy_Camera"))
        #expect(PermissionKind.microphone.settingsURL.absoluteString.contains("Privacy_Microphone"))
    }
}
