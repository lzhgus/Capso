import Foundation
import CoreGraphics
@preconcurrency import ScreenCaptureKit

public struct WindowInfo: Identifiable, Sendable {
    public let id: CGWindowID
    public let title: String
    public let appName: String
    public let appBundleIdentifier: String?
    public let frame: CGRect
    public let isOnScreen: Bool
    public let windowLayer: Int

    public init(from scWindow: SCWindow) {
        let trimmedTitle = scWindow.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackTitle = scWindow.owningApplication?.applicationName ?? "Untitled Window"
        self.id = scWindow.windowID
        self.title = trimmedTitle.isEmpty ? fallbackTitle : trimmedTitle
        self.appName = scWindow.owningApplication?.applicationName ?? ""
        self.appBundleIdentifier = scWindow.owningApplication?.bundleIdentifier
        self.frame = scWindow.frame
        self.isOnScreen = scWindow.isOnScreen
        self.windowLayer = scWindow.windowLayer
    }
}

public struct DisplayInfo: Identifiable, Sendable {
    public let id: CGDirectDisplayID
    public let width: Int
    public let height: Int
    public let frame: CGRect

    public init(from scDisplay: SCDisplay) {
        self.id = scDisplay.displayID
        self.width = scDisplay.width
        self.height = scDisplay.height
        self.frame = scDisplay.frame
    }
}

public enum ContentEnumerator {
    public static func windows() async throws -> [WindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let myBundleID = Bundle.main.bundleIdentifier
        return content.windows
            .filter { window in
                let trimmedTitle = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let appName = window.owningApplication?.applicationName ?? ""

                return isCaptureCandidate(
                    frame: window.frame,
                    isOnScreen: window.isOnScreen,
                    title: trimmedTitle,
                    appName: appName,
                    hasOwningApplication: window.owningApplication != nil,
                    windowLayer: window.windowLayer,
                    isOwnAppWindow: window.owningApplication?.bundleIdentifier == myBundleID
                )
            }
            .map { WindowInfo(from: $0) }
    }

    static func isCaptureCandidate(
        frame: CGRect,
        isOnScreen: Bool,
        title: String,
        appName: String,
        hasOwningApplication: Bool,
        windowLayer: Int,
        isOwnAppWindow: Bool
    ) -> Bool {
        let hasUsableLabel = !title.isEmpty || !appName.isEmpty
        let isSystemMenuBar = !hasOwningApplication
            && windowLayer == Int(CGWindowLevelForKey(.mainMenuWindow))
        let isElevatedApplicationWindow = hasOwningApplication
            && windowLayer > 0
            && windowLayer < Int(CGWindowLevelForKey(.screenSaverWindow))
        let hasUsableSize = frame.width > 100
            && (frame.height > 50 || (isSystemMenuBar && frame.height >= 20))

        return hasUsableSize
            && isOnScreen
            && (hasOwningApplication || isSystemMenuBar)
            && hasUsableLabel
            && (windowLayer == 0
                || isOwnAppWindow
                || isElevatedApplicationWindow
                || isSystemMenuBar)
    }

    public static func displays() async throws -> [DisplayInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return content.displays.map { DisplayInfo(from: $0) }
    }

    public static func scWindow(for windowID: CGWindowID) async throws -> SCWindow? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return content.windows.first { $0.windowID == windowID }
    }

    public static func scDisplay(for displayID: CGDirectDisplayID) async throws -> SCDisplay? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return content.displays.first { $0.displayID == displayID }
    }

    public static func mainDisplay() async throws -> SCDisplay? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return content.displays.first { $0.displayID == CGMainDisplayID() }
    }
}
