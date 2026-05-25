import AppKit
import AVFoundation
import Observation
@preconcurrency import ScreenCaptureKit

public enum PermissionKind: String, CaseIterable, Sendable {
    case screenRecording
    case accessibility
    case camera
    case microphone

    public var settingsURL: URL {
        switch self {
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .camera:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        }
    }
}

@Observable
@MainActor
public final class PermissionManager {
    public private(set) var screenRecordingGranted: Bool = false
    public private(set) var cameraGranted: Bool = false
    public private(set) var microphoneGranted: Bool = false
    public private(set) var accessibilityGranted: Bool = false

    public init() {}

    public func refreshAll() async {
        await checkScreenRecordingPermission()
        checkAccessibilityPermission()
        checkCameraPermission()
        checkMicrophonePermission()
    }

    // MARK: - Screen Recording

    public func checkScreenRecordingPermission() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            screenRecordingGranted = true
        } catch {
            screenRecordingGranted = false
        }
    }

    // MARK: - Camera

    public func checkCameraPermission() {
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    public func requestCameraPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraGranted = true
        case .notDetermined:
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            cameraGranted = false
        }
    }

    // MARK: - Microphone

    public func checkMicrophonePermission() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public func requestMicrophonePermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            microphoneGranted = true
        case .notDetermined:
            microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            microphoneGranted = false
        }
    }

    // MARK: - Accessibility

    public func checkAccessibilityPermission() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permission.
    /// Opens System Settings if not yet trusted.
    public func requestAccessibilityPermission() {
        // AXIsProcessTrustedWithOptions with prompt option
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Open System Settings

    public func openScreenRecordingSettings() {
        openSettings(for: .screenRecording)
    }

    public func openCameraSettings() {
        openSettings(for: .camera)
    }

    public func openMicrophoneSettings() {
        openSettings(for: .microphone)
    }

    public func openAccessibilitySettings() {
        openSettings(for: .accessibility)
    }

    public func openSettings(for kind: PermissionKind) {
        NSWorkspace.shared.open(kind.settingsURL)
    }
}
