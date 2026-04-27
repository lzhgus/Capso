import Foundation
import CoreGraphics

// MARK: - Enums

public enum ScreenshotFormat: String, CaseIterable, Sendable {
    case png
    case jpeg
}

public enum QuickAccessPosition: String, CaseIterable, Sendable {
    case bottomLeft
    case bottomRight
}

public enum RecordingFormat: String, CaseIterable, Sendable {
    case mp4
    case gif
}

public enum TranslationCardPosition: String, CaseIterable, Sendable {
    case belowSelection
    case centerScreen
    case rememberLast
}

public enum TranslationAutoDismiss: String, CaseIterable, Sendable {
    case manual
    case clickOutside
    case afterDelay
}

public enum ExportQuality: String, CaseIterable, Sendable {
    case maximum
    case social
    case web
}

public enum CameraShape: String, CaseIterable, Sendable {
    case circle
    case square     // 1:1 with rounded corners
    case landscape  // 16:9
    case portrait   // 9:16

    /// Aspect ratio (width / height) for this shape.
    public var aspectRatio: CGFloat {
        switch self {
        case .circle, .square: return 1.0
        case .landscape: return 16.0 / 9.0
        case .portrait: return 9.0 / 16.0
        }
    }
}

public enum CameraSize: String, CaseIterable, Sendable {
    case small   // 100pt shorter dimension
    case medium  // 150pt
    case large   // 220pt

    /// Length of the shorter dimension in points.
    public var shorterDimension: CGFloat {
        switch self {
        case .small: return 100
        case .medium: return 150
        case .large: return 220
        }
    }
}

// MARK: - AppSettings

/// Holds every user-configurable setting with sensible defaults.
/// Backed by `UserDefaults` so all settings are persisted automatically.
/// Pass a custom `UserDefaults` suite (e.g. `UserDefaults(suiteName: "test")`) in tests
/// to avoid polluting real user preferences.
public final class AppSettings: @unchecked Sendable {
    private let defaults: UserDefaults

    // MARK: General
    public var startAtLogin: Bool {
        get { defaults.object(forKey: "startAtLogin") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "startAtLogin") }
    }

    public var playShutterSound: Bool {
        get { defaults.object(forKey: "playShutterSound") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "playShutterSound") }
    }

    public var showMenuBarIcon: Bool {
        get { defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showMenuBarIcon") }
    }

    // MARK: Export
    public var screenshotFormat: ScreenshotFormat {
        get {
            guard let raw = defaults.string(forKey: "screenshotFormat"),
                  let value = ScreenshotFormat(rawValue: raw) else { return .png }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: "screenshotFormat") }
    }

    public var recordingFormat: RecordingFormat {
        get {
            guard let raw = defaults.string(forKey: "recordingFormat"),
                  let value = RecordingFormat(rawValue: raw) else { return .mp4 }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: "recordingFormat") }
    }

    public var exportQuality: ExportQuality {
        get {
            guard let raw = defaults.string(forKey: "exportQuality"),
                  let value = ExportQuality(rawValue: raw) else { return .maximum }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: "exportQuality") }
    }

    // MARK: Quick Access
    public var quickAccessPosition: QuickAccessPosition {
        get {
            guard let raw = defaults.string(forKey: "quickAccessPosition"),
                  let value = QuickAccessPosition(rawValue: raw) else { return .bottomLeft }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: "quickAccessPosition") }
    }

    public var quickAccessAutoClose: Bool {
        get { defaults.object(forKey: "quickAccessAutoClose") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "quickAccessAutoClose") }
    }

    public var quickAccessAutoCloseInterval: Int {
        get { defaults.object(forKey: "quickAccessAutoCloseInterval") as? Int ?? 5 }
        set { defaults.set(newValue, forKey: "quickAccessAutoCloseInterval") }
    }

    // MARK: Recording
    public var showCursor: Bool {
        get { defaults.object(forKey: "showCursor") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showCursor") }
    }

    public var highlightClicks: Bool {
        get { defaults.object(forKey: "highlightClicks") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "highlightClicks") }
    }

    public var cursorSmoothing: Bool {
        get { defaults.object(forKey: "cursorSmoothing") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "cursorSmoothing") }
    }

    public var dimScreenWhileRecording: Bool {
        get { defaults.object(forKey: "dimScreenWhileRecording") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "dimScreenWhileRecording") }
    }

    public var showCountdown: Bool {
        get { defaults.object(forKey: "showCountdown") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showCountdown") }
    }

    public var rememberLastRecordingArea: Bool {
        get { defaults.object(forKey: "rememberLastRecordingArea") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "rememberLastRecordingArea") }
    }

    /// When `true`, the recording editor opens after every recording stops.
    /// When `false` (default), the quick-preview flow is used instead.
    /// Default is `false` to preserve existing behaviour for existing users.
    public var openEditorAfterRecording: Bool {
        get { defaults.object(forKey: "openEditorAfterRecording") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "openEditorAfterRecording") }
    }

    // MARK: Camera
    public var cameraShape: CameraShape {
        get {
            guard let raw = defaults.string(forKey: "cameraShape"),
                  let value = CameraShape(rawValue: raw) else { return .circle }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: "cameraShape") }
    }

    public var cameraSize: CameraSize {
        get {
            guard let raw = defaults.string(forKey: "cameraSize"),
                  let value = CameraSize(rawValue: raw) else { return .medium }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: "cameraSize") }
    }

    public var cameraMirror: Bool {
        get { defaults.object(forKey: "cameraMirror") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "cameraMirror") }
    }

    /// Custom size (shorter dimension in points). 0 means use the cameraSize preset.
    /// Set when the user drags the corner resize handle.
    public var cameraCustomSizePt: Double {
        get { defaults.object(forKey: "cameraCustomSizePt") as? Double ?? 0 }
        set { defaults.set(newValue, forKey: "cameraCustomSizePt") }
    }

    // MARK: Screenshots
    public var screenshotShowPreview: Bool {
        get { defaults.object(forKey: "screenshotShowPreview") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "screenshotShowPreview") }
    }

    public var screenshotAutoCopy: Bool {
        get { defaults.object(forKey: "screenshotAutoCopy") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "screenshotAutoCopy") }
    }

    public var screenshotAutoSave: Bool {
        get { defaults.object(forKey: "screenshotAutoSave") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "screenshotAutoSave") }
    }

    public var captureWindowShadow: Bool {
        get { defaults.object(forKey: "captureWindowShadow") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "captureWindowShadow") }
    }

    public var freezeScreen: Bool {
        get { defaults.object(forKey: "freezeScreen") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "freezeScreen") }
    }

    public var showMagnifier: Bool {
        get { defaults.object(forKey: "showMagnifier") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showMagnifier") }
    }

    public var rememberLastCaptureArea: Bool {
        get { defaults.object(forKey: "rememberLastCaptureArea") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "rememberLastCaptureArea") }
    }

    // MARK: Capture Presets

    public var capturePresetsEnabled: Bool {
        get { defaults.object(forKey: "capturePresetsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "capturePresetsEnabled") }
    }

    public var capturePreset: CapturePreset {
        get {
            guard let data = defaults.data(forKey: "capturePreset"),
                  let value = try? JSONDecoder().decode(CapturePreset.self, from: data) else {
                return .freeform
            }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "capturePreset")
            }
        }
    }

    public var customCapturePresets: [CapturePreset] {
        get {
            guard let data = defaults.data(forKey: "customCapturePresets"),
                  let value = try? JSONDecoder().decode([CapturePreset].self, from: data) else {
                return []
            }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "customCapturePresets")
            }
        }
    }

    public var hiddenBuiltinPresets: Set<CapturePreset> {
        get {
            guard let data = defaults.data(forKey: "hiddenBuiltinPresets"),
                  let value = try? JSONDecoder().decode(Set<CapturePreset>.self, from: data) else {
                return []
            }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "hiddenBuiltinPresets")
            }
        }
    }

    /// All visible presets in display order: visible built-ins then custom.
    public var visiblePresets: [CapturePreset] {
        let builtins = CapturePreset.allBuiltins.filter { !hiddenBuiltinPresets.contains($0) }
        return builtins + customCapturePresets
    }

    // MARK: History
    public var historyEnabled: Bool {
        get { defaults.object(forKey: "historyEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "historyEnabled") }
    }

    /// Raw string value matching HistoryRetention enum in HistoryKit.
    public var historyRetention: String {
        get { defaults.string(forKey: "historyRetention") ?? "oneMonth" }
        set { defaults.set(newValue, forKey: "historyRetention") }
    }

    // MARK: OCR
    public var ocrKeepLineBreaks: Bool {
        get { defaults.object(forKey: "ocrKeepLineBreaks") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ocrKeepLineBreaks") }
    }

    public var ocrDetectLinks: Bool {
        get { defaults.object(forKey: "ocrDetectLinks") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ocrDetectLinks") }
    }

    public var ocrPrimaryLanguage: String? {
        get { defaults.string(forKey: "ocrPrimaryLanguage") }
        set { defaults.set(newValue, forKey: "ocrPrimaryLanguage") }
    }

    public var ocrOnboardingShown: Bool {
        get { defaults.object(forKey: "ocrOnboardingShown") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "ocrOnboardingShown") }
    }

    // MARK: Translation
    public var translationTargetLanguage: String {
        get {
            defaults.string(forKey: "translationTargetLanguage") ?? Self.systemDefaultLanguage()
        }
        set { defaults.set(newValue, forKey: "translationTargetLanguage") }
    }

    public var translationAutoCopy: Bool {
        get { defaults.object(forKey: "translationAutoCopy") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "translationAutoCopy") }
    }

    public var translationShowOriginal: Bool {
        get { defaults.object(forKey: "translationShowOriginal") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "translationShowOriginal") }
    }

    public var translationCardPosition: TranslationCardPosition {
        get {
            guard let raw = defaults.string(forKey: "translationCardPosition"),
                  let value = TranslationCardPosition(rawValue: raw) else { return .centerScreen }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: "translationCardPosition") }
    }

    public var translationAutoDismiss: TranslationAutoDismiss {
        get {
            guard let raw = defaults.string(forKey: "translationAutoDismiss"),
                  let value = TranslationAutoDismiss(rawValue: raw) else { return .manual }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: "translationAutoDismiss") }
    }

    public var translationAutoDismissDelay: TimeInterval {
        get { defaults.object(forKey: "translationAutoDismissDelay") as? TimeInterval ?? 10 }
        set { defaults.set(newValue, forKey: "translationAutoDismissDelay") }
    }

    public var translationOnboardingShown: Bool {
        get { defaults.object(forKey: "translationOnboardingShown") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "translationOnboardingShown") }
    }

    /// Chosen at first launch; falls back to English for unsupported locales.
    /// Kept here (rather than in TranslationKit) so SharedKit has no extra dependency.
    private static func systemDefaultLanguage() -> String {
        let locale = Locale.current
        guard let code = locale.language.languageCode?.identifier else { return "en" }
        if code == "zh" {
            let script = locale.language.script?.identifier
            let region = locale.region?.identifier
            let traditionalRegions: Set<String> = ["TW", "HK", "MO"]
            let isTraditional = script == "Hant"
                || (script == nil && region.map(traditionalRegions.contains) == true)
            return isTraditional ? "zh-Hant" : "zh-Hans"
        }
        if code == "pt" { return "pt-BR" }
        let supported: Set<String> = [
            "ar", "de", "en", "es", "fr", "hi", "id", "it", "ja", "ko",
            "nl", "pl", "ru", "tr", "uk"
        ]
        return supported.contains(code) ? code : "en"
    }

    // MARK: Licensing
    public var isProUnlocked: Bool {
        get { defaults.object(forKey: "isProUnlocked") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "isProUnlocked") }
    }

    public var trialStartDate: Double {
        get { defaults.object(forKey: "trialStartDate") as? Double ?? 0 }
        set { defaults.set(newValue, forKey: "trialStartDate") }
    }

    // MARK: Export Location

    public var exportLocation: URL {
        if let custom = defaults.url(forKey: "exportLocation") {
            return custom
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    }

    public func setExportLocation(_ url: URL) {
        defaults.set(url, forKey: "exportLocation")
    }

    // MARK: Cloud Share

    public var cloudShareProvider: String? {
        get { defaults.string(forKey: "cloudShareProvider") }
        set { defaults.set(newValue, forKey: "cloudShareProvider") }
    }

    public var cloudShareURLPrefix: String? {
        get { defaults.string(forKey: "cloudShareURLPrefix") }
        set { defaults.set(newValue, forKey: "cloudShareURLPrefix") }
    }

    public var cloudShareAccountID: String? {
        get { defaults.string(forKey: "cloudShareAccountID") }
        set { defaults.set(newValue, forKey: "cloudShareAccountID") }
    }

    public var cloudShareBucket: String? {
        get { defaults.string(forKey: "cloudShareBucket") }
        set { defaults.set(newValue, forKey: "cloudShareBucket") }
    }

    public var isCloudShareConfigured: Bool {
        cloudShareProvider != nil
            && cloudShareURLPrefix != nil
            && cloudShareAccountID != nil
            && cloudShareBucket != nil
    }

    // MARK: Computed

    public var isTrialActive: Bool {
        guard !isProUnlocked else { return false }
        guard trialStartDate > 0 else { return false }
        let start = Date(timeIntervalSince1970: trialStartDate)
        let daysSinceStart = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return daysSinceStart < 7
    }

    public var trialDaysRemaining: Int {
        guard isTrialActive else { return 0 }
        let start = Date(timeIntervalSince1970: trialStartDate)
        let daysSinceStart = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return max(0, 7 - daysSinceStart)
    }

    public var hasProAccess: Bool {
        isProUnlocked || isTrialActive
    }

    public func startTrial() {
        if trialStartDate == 0 {
            trialStartDate = Date().timeIntervalSince1970
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
}
