// App/Sources/Preferences/PreferencesViewModel.swift
import Foundation
import Observation
import SharedKit
import TranslationKit

@MainActor
@Observable
final class PreferencesViewModel {
    private let settings: AppSettings
    private let permissionManager: PermissionManager

    private(set) var screenRecordingGranted: Bool = false
    private(set) var accessibilityGranted: Bool = false
    private(set) var cameraGranted: Bool = false
    private(set) var microphoneGranted: Bool = false

    private static let filenamePreviewDate: Date = {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = 2026
        components.month = 6
        components.day = 7
        components.hour = 16
        components.minute = 11
        components.second = 23
        return components.date ?? Date(timeIntervalSince1970: 0)
    }()

    init(settings: AppSettings, permissionManager: PermissionManager) {
        self.settings = settings
        self.permissionManager = permissionManager
    }

    // MARK: General
    var playShutterSound: Bool {
        get {
            access(keyPath: \.playShutterSound)
            return settings.playShutterSound
        }
        set {
            withMutation(keyPath: \.playShutterSound) {
                settings.playShutterSound = newValue
            }
        }
    }
    var showMenuBarIcon: Bool {
        get {
            access(keyPath: \.showMenuBarIcon)
            return settings.showMenuBarIcon
        }
        set {
            withMutation(keyPath: \.showMenuBarIcon) {
                settings.showMenuBarIcon = newValue
            }
            NotificationCenter.default.post(name: .menuBarVisibilityChanged, object: nil)
        }
    }
    var diagnosticLoggingEnabled: Bool {
        get {
            access(keyPath: \.diagnosticLoggingEnabled)
            return settings.diagnosticLoggingEnabled
        }
        set {
            withMutation(keyPath: \.diagnosticLoggingEnabled) {
                settings.diagnosticLoggingEnabled = newValue
            }
        }
    }
    var automationURLsEnabled: Bool {
        get {
            access(keyPath: \.automationURLsEnabled)
            return settings.automationURLsEnabled
        }
        set {
            withMutation(keyPath: \.automationURLsEnabled) {
                settings.automationURLsEnabled = newValue
            }
        }
    }

    // MARK: Screenshots
    var screenshotShowPreview: Bool {
        get {
            access(keyPath: \.screenshotShowPreview)
            return settings.screenshotShowPreview
        }
        set {
            withMutation(keyPath: \.screenshotShowPreview) {
                settings.screenshotShowPreview = newValue
            }
        }
    }
    var screenshotAutoCopy: Bool {
        get {
            access(keyPath: \.screenshotAutoCopy)
            return settings.screenshotAutoCopy
        }
        set {
            withMutation(keyPath: \.screenshotAutoCopy) {
                settings.screenshotAutoCopy = newValue
            }
        }
    }
    var screenshotAutoSave: Bool {
        get {
            access(keyPath: \.screenshotAutoSave)
            return settings.screenshotAutoSave
        }
        set {
            withMutation(keyPath: \.screenshotAutoSave) {
                settings.screenshotAutoSave = newValue
            }
        }
    }
    var screenshotOutputPreset: ScreenshotOutputPreset {
        get {
            access(keyPath: \.screenshotOutputPreset)
            return settings.screenshotOutputPreset
        }
        set {
            withMutation(keyPath: \.screenshotOutputPreset) {
                settings.screenshotOutputPreset = newValue
            }
        }
    }
    var screenshotMonthlyFolders: Bool {
        get {
            access(keyPath: \.screenshotMonthlyFolders)
            return settings.screenshotMonthlyFolders
        }
        set {
            withMutation(keyPath: \.screenshotMonthlyFolders) {
                settings.screenshotMonthlyFolders = newValue
            }
        }
    }
    var screenshotShowsCursor: Bool {
        get {
            access(keyPath: \.screenshotShowsCursor)
            return settings.screenshotShowsCursor
        }
        set {
            withMutation(keyPath: \.screenshotShowsCursor) {
                settings.screenshotShowsCursor = newValue
            }
        }
    }
    var screenshotTimestampEnabled: Bool {
        get {
            access(keyPath: \.screenshotTimestampEnabled)
            return settings.screenshotTimestampEnabled
        }
        set {
            withMutation(keyPath: \.screenshotTimestampEnabled) {
                settings.screenshotTimestampEnabled = newValue
            }
        }
    }
    var screenshotTimestampPosition: ScreenshotTimestampPosition {
        get {
            access(keyPath: \.screenshotTimestampPosition)
            return settings.screenshotTimestampPosition
        }
        set {
            withMutation(keyPath: \.screenshotTimestampPosition) {
                settings.screenshotTimestampPosition = newValue
            }
        }
    }
    var screenshotTimestampFormat: ScreenshotTimestampFormat {
        get {
            access(keyPath: \.screenshotTimestampFormat)
            return settings.screenshotTimestampFormat
        }
        set {
            withMutation(keyPath: \.screenshotTimestampFormat) {
                settings.screenshotTimestampFormat = newValue
            }
        }
    }
    var screenshotTimestampColorHex: String {
        get {
            access(keyPath: \.screenshotTimestampColorHex)
            return settings.screenshotTimestampColorHex
        }
        set {
            withMutation(keyPath: \.screenshotTimestampColorHex) {
                settings.screenshotTimestampColorHex = newValue
            }
        }
    }
    var screenshotTimestampFontSize: Int {
        get {
            access(keyPath: \.screenshotTimestampFontSize)
            return settings.screenshotTimestampFontSize
        }
        set {
            withMutation(keyPath: \.screenshotTimestampFontSize) {
                settings.screenshotTimestampFontSize = newValue
            }
        }
    }
    var captureWindowShadow: Bool {
        get {
            access(keyPath: \.captureWindowShadow)
            return settings.captureWindowShadow
        }
        set {
            withMutation(keyPath: \.captureWindowShadow) {
                settings.captureWindowShadow = newValue
            }
        }
    }
    var showMagnifier: Bool {
        get {
            access(keyPath: \.showMagnifier)
            return settings.showMagnifier
        }
        set {
            withMutation(keyPath: \.showMagnifier) {
                settings.showMagnifier = newValue
            }
        }
    }
    // MARK: Self-Timer
    var selfTimerDurationSeconds: Int {
        get {
            access(keyPath: \.selfTimerDurationSeconds)
            return settings.selfTimerDurationSeconds
        }
        set {
            withMutation(keyPath: \.selfTimerDurationSeconds) {
                settings.selfTimerDurationSeconds = newValue
            }
        }
    }
    var selfTimerPlayTickSound: Bool {
        get {
            access(keyPath: \.selfTimerPlayTickSound)
            return settings.selfTimerPlayTickSound
        }
        set {
            withMutation(keyPath: \.selfTimerPlayTickSound) {
                settings.selfTimerPlayTickSound = newValue
            }
        }
    }

    // MARK: Capture Presets
    var capturePresetsEnabled: Bool {
        get {
            access(keyPath: \.capturePresetsEnabled)
            return settings.capturePresetsEnabled
        }
        set {
            withMutation(keyPath: \.capturePresetsEnabled) {
                settings.capturePresetsEnabled = newValue
            }
        }
    }
    var capturePreset: CapturePreset {
        get {
            access(keyPath: \.capturePreset)
            return settings.capturePreset
        }
        set {
            withMutation(keyPath: \.capturePreset) {
                settings.capturePreset = newValue
            }
        }
    }
    var customCapturePresets: [CapturePreset] {
        get {
            access(keyPath: \.customCapturePresets)
            return settings.customCapturePresets
        }
        set {
            withMutation(keyPath: \.customCapturePresets) {
                settings.customCapturePresets = newValue
            }
        }
    }
    var hiddenBuiltinPresets: Set<CapturePreset> {
        get {
            access(keyPath: \.hiddenBuiltinPresets)
            return settings.hiddenBuiltinPresets
        }
        set {
            withMutation(keyPath: \.hiddenBuiltinPresets) {
                settings.hiddenBuiltinPresets = newValue
            }
        }
    }

    // MARK: Recording
    var recordingFormat: RecordingFormat {
        get {
            access(keyPath: \.recordingFormat)
            return settings.recordingFormat
        }
        set {
            withMutation(keyPath: \.recordingFormat) {
                settings.recordingFormat = newValue
            }
        }
    }
    var showCursor: Bool {
        get {
            access(keyPath: \.showCursor)
            return settings.showCursor
        }
        set {
            withMutation(keyPath: \.showCursor) {
                settings.showCursor = newValue
            }
        }
    }
    var highlightClicks: Bool {
        get {
            access(keyPath: \.highlightClicks)
            return settings.highlightClicks
        }
        set {
            withMutation(keyPath: \.highlightClicks) {
                settings.highlightClicks = newValue
            }
        }
    }
    var cursorSmoothing: Bool {
        get {
            access(keyPath: \.cursorSmoothing)
            return settings.cursorSmoothing
        }
        set {
            withMutation(keyPath: \.cursorSmoothing) {
                settings.cursorSmoothing = newValue
            }
        }
    }
    var showCountdown: Bool {
        get {
            access(keyPath: \.showCountdown)
            return settings.showCountdown
        }
        set {
            withMutation(keyPath: \.showCountdown) {
                settings.showCountdown = newValue
            }
        }
    }
    var openEditorAfterRecording: Bool {
        get {
            access(keyPath: \.openEditorAfterRecording)
            return settings.openEditorAfterRecording
        }
        set {
            withMutation(keyPath: \.openEditorAfterRecording) {
                settings.openEditorAfterRecording = newValue
            }
        }
    }
    var dimScreenWhileRecording: Bool {
        get {
            access(keyPath: \.dimScreenWhileRecording)
            return settings.dimScreenWhileRecording
        }
        set {
            withMutation(keyPath: \.dimScreenWhileRecording) {
                settings.dimScreenWhileRecording = newValue
            }
        }
    }
    var rememberLastRecordingArea: Bool {
        get {
            access(keyPath: \.rememberLastRecordingArea)
            return settings.rememberLastRecordingArea
        }
        set {
            withMutation(keyPath: \.rememberLastRecordingArea) {
                settings.rememberLastRecordingArea = newValue
            }
        }
    }

    // MARK: Camera
    var cameraShape: CameraShape {
        get {
            access(keyPath: \.cameraShape)
            return settings.cameraShape
        }
        set {
            withMutation(keyPath: \.cameraShape) {
                settings.cameraShape = newValue
            }
        }
    }
    var cameraSize: CameraSize {
        get {
            access(keyPath: \.cameraSize)
            return settings.cameraSize
        }
        set {
            withMutation(keyPath: \.cameraSize) {
                settings.cameraSize = newValue
            }
        }
    }
    var cameraMirror: Bool {
        get {
            access(keyPath: \.cameraMirror)
            return settings.cameraMirror
        }
        set {
            withMutation(keyPath: \.cameraMirror) {
                settings.cameraMirror = newValue
            }
        }
    }
    var cameraCustomSizePt: Double {
        get {
            access(keyPath: \.cameraCustomSizePt)
            return settings.cameraCustomSizePt
        }
        set {
            withMutation(keyPath: \.cameraCustomSizePt) {
                settings.cameraCustomSizePt = newValue
            }
        }
    }

    // MARK: Quick Access
    var quickAccessPosition: QuickAccessPosition {
        get {
            access(keyPath: \.quickAccessPosition)
            return settings.quickAccessPosition
        }
        set {
            withMutation(keyPath: \.quickAccessPosition) {
                settings.quickAccessPosition = newValue
            }
        }
    }
    var quickAccessAutoClose: Bool {
        get {
            access(keyPath: \.quickAccessAutoClose)
            return settings.quickAccessAutoClose
        }
        set {
            withMutation(keyPath: \.quickAccessAutoClose) {
                settings.quickAccessAutoClose = newValue
            }
        }
    }
    var quickAccessAutoCloseInterval: Int {
        get {
            access(keyPath: \.quickAccessAutoCloseInterval)
            return settings.quickAccessAutoCloseInterval
        }
        set {
            withMutation(keyPath: \.quickAccessAutoCloseInterval) {
                settings.quickAccessAutoCloseInterval = newValue
            }
        }
    }

    // MARK: Export
    var exportQuality: ExportQuality {
        get {
            access(keyPath: \.exportQuality)
            return settings.exportQuality
        }
        set {
            withMutation(keyPath: \.exportQuality) {
                settings.exportQuality = newValue
            }
        }
    }
    var exportLocation: URL {
        access(keyPath: \.exportLocation)
        return settings.exportLocation
    }
    func setExportLocation(_ url: URL) {
        withMutation(keyPath: \.exportLocation) {
            settings.setExportLocation(url)
        }
    }
    var screenshotFilenameTemplate: String {
        get {
            access(keyPath: \.screenshotFilenameTemplate)
            return settings.screenshotFilenameTemplate
        }
        set {
            withMutation(keyPath: \.screenshotFilenameTemplate) {
                settings.screenshotFilenameTemplate = newValue
            }
        }
    }
    func resetScreenshotFilenameTemplate() {
        screenshotFilenameTemplate = FileNaming.defaultScreenshotTemplate
    }
    var screenshotFilenamePreview: String {
        FileNaming.generateFileName(
            for: .screenshot,
            format: screenshotOutputPreset.fileFormat,
            date: Self.filenamePreviewDate,
            sourceAppName: "Safari",
            sourceWindowTitle: "Example Window",
            template: screenshotFilenameTemplate
        )
    }

    // MARK: OCR
    var ocrKeepLineBreaks: Bool {
        get {
            access(keyPath: \.ocrKeepLineBreaks)
            return settings.ocrKeepLineBreaks
        }
        set {
            withMutation(keyPath: \.ocrKeepLineBreaks) {
                settings.ocrKeepLineBreaks = newValue
            }
        }
    }
    var ocrDetectLinks: Bool {
        get {
            access(keyPath: \.ocrDetectLinks)
            return settings.ocrDetectLinks
        }
        set {
            withMutation(keyPath: \.ocrDetectLinks) {
                settings.ocrDetectLinks = newValue
            }
        }
    }
    var ocrPrimaryLanguage: String? {
        get {
            access(keyPath: \.ocrPrimaryLanguage)
            return settings.ocrPrimaryLanguage
        }
        set {
            withMutation(keyPath: \.ocrPrimaryLanguage) {
                settings.ocrPrimaryLanguage = newValue
            }
        }
    }

    // MARK: Translation
    var translationTargetLanguage: String {
        get {
            access(keyPath: \.translationTargetLanguage)
            return settings.translationTargetLanguage
        }
        set {
            withMutation(keyPath: \.translationTargetLanguage) {
                settings.translationTargetLanguage = newValue
            }
        }
    }
    var translationProvider: TranslationProviderKind {
        get {
            access(keyPath: \.translationProvider)
            return settings.translationProvider
        }
        set {
            withMutation(keyPath: \.translationProvider) {
                settings.translationProvider = newValue
            }
        }
    }
    var translationProviderModel: String {
        get {
            access(keyPath: \.translationProviderModel)
            return settings.translationProviderModel
        }
        set {
            withMutation(keyPath: \.translationProviderModel) {
                settings.translationProviderModel = newValue
            }
        }
    }
    var translationProviderEndpoint: String {
        get {
            access(keyPath: \.translationProviderEndpoint)
            return settings.translationProviderEndpoint
        }
        set {
            withMutation(keyPath: \.translationProviderEndpoint) {
                settings.translationProviderEndpoint = newValue
            }
        }
    }
    func translationAPIKey() -> String {
        settings.translationAPIKey() ?? ""
    }
    func setTranslationAPIKey(_ value: String) throws {
        try settings.setTranslationAPIKey(value)
    }
    func testTranslationProviderConnection() async throws {
        let provider = settings.translationProvider
        guard provider != .apple else { return }
        let result = try await ProviderTranslationService.translate(
            text: "hello",
            target: settings.translationTargetLanguage,
            provider: provider,
            config: TranslationProviderConfiguration(
                apiKey: settings.translationAPIKey() ?? "",
                endpoint: settings.translationProviderEndpoint,
                model: settings.translationProviderModel
            )
        )
        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProviderTranslationError.badResponse
        }
    }
    var translationAutoCopy: Bool {
        get {
            access(keyPath: \.translationAutoCopy)
            return settings.translationAutoCopy
        }
        set {
            withMutation(keyPath: \.translationAutoCopy) {
                settings.translationAutoCopy = newValue
            }
        }
    }
    var translationShowOriginal: Bool {
        get {
            access(keyPath: \.translationShowOriginal)
            return settings.translationShowOriginal
        }
        set {
            withMutation(keyPath: \.translationShowOriginal) {
                settings.translationShowOriginal = newValue
            }
        }
    }
    var translationAutoDismiss: TranslationAutoDismiss {
        get {
            access(keyPath: \.translationAutoDismiss)
            return settings.translationAutoDismiss
        }
        set {
            withMutation(keyPath: \.translationAutoDismiss) {
                settings.translationAutoDismiss = newValue
            }
        }
    }

    // MARK: Permissions
    func refreshPermissions() async {
        await permissionManager.refreshAll()
        updatePermissionSnapshot()
    }

    func requestPermission(_ kind: PermissionKind) async {
        switch kind {
        case .screenRecording:
            permissionManager.openSettings(for: kind)
        case .accessibility:
            permissionManager.requestAccessibilityPermission()
            permissionManager.openSettings(for: kind)
        case .camera:
            await permissionManager.requestCameraPermission()
        case .microphone:
            await permissionManager.requestMicrophonePermission()
        }
        updatePermissionSnapshot()
    }

    func openPermissionSettings(_ kind: PermissionKind) {
        permissionManager.openSettings(for: kind)
    }

    private func updatePermissionSnapshot() {
        screenRecordingGranted = permissionManager.screenRecordingGranted
        accessibilityGranted = permissionManager.accessibilityGranted
        cameraGranted = permissionManager.cameraGranted
        microphoneGranted = permissionManager.microphoneGranted
    }

    // MARK: Cloud Share
    var isCloudShareConfigured: Bool {
        access(keyPath: \.isCloudShareConfigured)
        return settings.isCloudShareConfigured
    }
    var cloudShareProvider: String? {
        get {
            access(keyPath: \.cloudShareProvider)
            return settings.cloudShareProvider
        }
        set {
            withMutation(keyPath: \.cloudShareProvider) {
                withMutation(keyPath: \.isCloudShareConfigured) {
                    settings.cloudShareProvider = newValue
                }
            }
        }
    }
    var cloudShareURLPrefix: String? {
        get {
            access(keyPath: \.cloudShareURLPrefix)
            return settings.cloudShareURLPrefix
        }
        set {
            withMutation(keyPath: \.cloudShareURLPrefix) {
                withMutation(keyPath: \.isCloudShareConfigured) {
                    settings.cloudShareURLPrefix = newValue
                }
            }
        }
    }
    var cloudShareAccountID: String? {
        get {
            access(keyPath: \.cloudShareAccountID)
            return settings.cloudShareAccountID
        }
        set {
            withMutation(keyPath: \.cloudShareAccountID) {
                withMutation(keyPath: \.isCloudShareConfigured) {
                    settings.cloudShareAccountID = newValue
                }
            }
        }
    }
    var cloudShareBucket: String? {
        get {
            access(keyPath: \.cloudShareBucket)
            return settings.cloudShareBucket
        }
        set {
            withMutation(keyPath: \.cloudShareBucket) {
                withMutation(keyPath: \.isCloudShareConfigured) {
                    settings.cloudShareBucket = newValue
                }
            }
        }
    }
    var cloudShareRegion: String? {
        get {
            access(keyPath: \.cloudShareRegion)
            return settings.cloudShareRegion
        }
        set {
            withMutation(keyPath: \.cloudShareRegion) {
                withMutation(keyPath: \.isCloudShareConfigured) {
                    settings.cloudShareRegion = newValue
                }
            }
        }
    }
    var cloudShareEndpoint: String? {
        get {
            access(keyPath: \.cloudShareEndpoint)
            return settings.cloudShareEndpoint
        }
        set {
            withMutation(keyPath: \.cloudShareEndpoint) {
                settings.cloudShareEndpoint = newValue
            }
        }
    }
    var cloudSharePathPrefix: String? {
        get {
            access(keyPath: \.cloudSharePathPrefix)
            return settings.cloudSharePathPrefix
        }
        set {
            withMutation(keyPath: \.cloudSharePathPrefix) {
                settings.cloudSharePathPrefix = newValue
            }
        }
    }
    var cloudShareAutoUploadEnabled: Bool {
        get {
            access(keyPath: \.cloudShareAutoUploadEnabled)
            return settings.cloudShareAutoUploadEnabled
        }
        set {
            withMutation(keyPath: \.cloudShareAutoUploadEnabled) {
                settings.cloudShareAutoUploadEnabled = newValue
            }
        }
    }

    // MARK: Version
    // MARK: History
    var historyEnabled: Bool {
        get {
            access(keyPath: \.historyEnabled)
            return settings.historyEnabled
        }
        set {
            withMutation(keyPath: \.historyEnabled) {
                settings.historyEnabled = newValue
            }
        }
    }

    var historyRetention: String {
        get {
            access(keyPath: \.historyRetention)
            return settings.historyRetention
        }
        set {
            withMutation(keyPath: \.historyRetention) {
                settings.historyRetention = newValue
            }
        }
    }

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
