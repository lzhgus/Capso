import Foundation
import CoreGraphics

// MARK: - Enums

public enum ScreenshotFormat: String, CaseIterable, Sendable {
    case png
    case jpeg
}

public enum ScreenshotClipboardFormat: String, CaseIterable, Sendable {
    case png
    case jpeg
    case tiff
}

public enum ScreenshotClipboardContent: String, CaseIterable, Sendable {
    case image
    case filePath
}

/// The still-image format screenshots are written in.
public enum ScreenshotOutputFormat: String, CaseIterable, Sendable {
    case png
    case jpeg
    case heic

    public static let qualityPercentRange: ClosedRange<Int> = 30...100

    public init?(_ fileFormat: FileFormat) {
        switch fileFormat {
        case .png:
            self = .png
        case .jpeg:
            self = .jpeg
        case .heic:
            self = .heic
        case .mp4, .gif, .mov:
            return nil
        }
    }

    public var fileFormat: FileFormat {
        switch self {
        case .png:
            return .png
        case .jpeg:
            return .jpeg
        case .heic:
            return .heic
        }
    }

    public var isLossy: Bool {
        self != .png
    }

    public var mimeType: String {
        fileFormat.contentType.preferredMIMEType ?? "image/png"
    }

    /// False when this Mac has no encoder for the format, as on Intel models lacking HEVC.
    public var isAvailable: Bool {
        ImageIOEncoder.writableTypeIdentifiers.contains(fileFormat.contentType.identifier)
    }
}

/// How screenshots are encoded: the format, plus the compression quality lossy formats use.
public struct ScreenshotOutputOptions: Equatable, Sendable {
    public let format: ScreenshotOutputFormat
    public let quality: Double

    public init(format: ScreenshotOutputFormat, quality: Double) {
        self.format = format
        self.quality = quality
    }
}

/// Superseded by `ScreenshotOutputFormat` plus a quality percentage; retained to migrate
/// defaults written by 1.0.1 and earlier and kept in sync for downgrade compatibility.
public enum ScreenshotOutputPreset: String, CaseIterable, Sendable {
    case losslessPNG
    case standardJPEG
    case compactJPEG

    public var fileFormat: FileFormat {
        switch self {
        case .losslessPNG:
            return .png
        case .standardJPEG, .compactJPEG:
            return .jpeg
        }
    }

    public var jpegQuality: Double? {
        switch self {
        case .losslessPNG:
            return nil
        case .standardJPEG:
            return 0.85
        case .compactJPEG:
            return 0.70
        }
    }

    var outputFormat: ScreenshotOutputFormat {
        switch self {
        case .losslessPNG:
            return .png
        case .standardJPEG, .compactJPEG:
            return .jpeg
        }
    }

    var qualityPercent: Int {
        switch self {
        case .losslessPNG, .standardJPEG:
            return 85
        case .compactJPEG:
            return 70
        }
    }
}

public enum QuickAccessPosition: String, CaseIterable, Sendable {
    case bottomLeft
    case centerScreen
    case bottomRight
}

public enum RecordingFormat: String, CaseIterable, Sendable {
    case mp4
    case gif
}

/// What Save does when annotating a file opened from disk (vs. a fresh capture).
public enum OpenedImageSaveBehavior: String, CaseIterable, Sendable {
    /// Prompt every time with "Overwrite Original" / "Save as New Copy".
    case ask
    /// Always overwrite the original file, preserving its format.
    case overwrite
    /// Always save a new file, exactly like a fresh capture.
    case copy
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

public enum TranslationProviderKind: String, CaseIterable, Sendable {
    case apple
    case openAICompatible
    case deepSeek
    case openRouter
    case deepL
    case googleCloud
    case custom

    public var displayName: String {
        switch self {
        case .apple: return "Apple Translation"
        case .openAICompatible: return "OpenAI"
        case .deepSeek: return "DeepSeek"
        case .openRouter: return "OpenRouter"
        case .deepL: return "DeepL"
        case .googleCloud: return "Google Cloud"
        case .custom: return "Custom"
        }
    }

    public var defaultEndpoint: String {
        switch self {
        case .apple:
            return ""
        case .openAICompatible:
            return "https://api.openai.com/v1/chat/completions"
        case .deepSeek:
            return "https://api.deepseek.com/chat/completions"
        case .openRouter:
            return "https://openrouter.ai/api/v1/chat/completions"
        case .deepL:
            return ""
        case .googleCloud:
            return "https://translation.googleapis.com/language/translate/v2"
        case .custom:
            return ""
        }
    }

    public var defaultModel: String {
        switch self {
        case .apple, .deepL, .googleCloud:
            return ""
        case .openAICompatible:
            return "gpt-4o-mini"
        case .deepSeek:
            return "deepseek-v4-flash"
        case .openRouter:
            return "openrouter/auto"
        case .custom:
            return ""
        }
    }

    public var requiresAPIKey: Bool {
        self != .apple
    }

    public var supportsModel: Bool {
        switch self {
        case .apple, .deepL, .googleCloud: return false
        case .openAICompatible, .deepSeek, .openRouter, .custom: return true
        }
    }

    public var supportsEndpoint: Bool {
        switch self {
        case .apple: return false
        case .openAICompatible, .deepSeek, .openRouter, .deepL, .googleCloud, .custom: return true
        }
    }

    public var supportsStreaming: Bool {
        switch self {
        case .openAICompatible, .deepSeek, .openRouter, .custom: return true
        case .apple, .deepL, .googleCloud: return false
        }
    }

    public var connectionSummary: String {
        switch self {
        case .apple:
            return "On-device · High-fidelity when available"
        case .deepL, .googleCloud:
            return "Cloud API · Complete response"
        case .custom:
            return "Configured endpoint · Streaming"
        case .openAICompatible, .deepSeek, .openRouter:
            return "Cloud API · Streaming"
        }
    }
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

/// The most recent capture, persisted so the user can replay it via the
/// "Capture Previous Area" global shortcut. Each case carries the
/// `CGDirectDisplayID` of the display the capture targeted.
///
/// Window mode is intentionally excluded. A saved `CGWindowID` is fragile:
/// the underlying window can move (Stage Manager, full-screen toggle,
/// virtual desktop), be reassigned to a different window after close, or
/// have its rendered size changed by the system out from under us. Replay
/// would silently produce a result that doesn't match the original capture.
/// Replay is limited to area and fullscreen, which are anchored to display
/// geometry rather than to a particular live window instance.
public enum StoredCaptureSelection: Codable, Sendable, Equatable {
    case area(x: Double, y: Double, width: Double, height: Double, screenID: UInt32)
    case fullscreen(screenID: UInt32)

    /// Convenience constructor flattening a `CGRect` into the case's fields.
    public static func area(rect: CGRect, screenID: UInt32) -> StoredCaptureSelection {
        .area(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height),
            screenID: screenID
        )
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

    public var diagnosticLoggingEnabled: Bool {
        get { defaults.object(forKey: "diagnosticLoggingEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "diagnosticLoggingEnabled") }
    }

    public var automationURLsEnabled: Bool {
        get { defaults.object(forKey: "automationURLsEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "automationURLsEnabled") }
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

    public var screenshotOutputFormat: ScreenshotOutputFormat {
        get {
            Self.resolvedOutputFormat(
                stored: defaults.string(forKey: "screenshotOutputFormat"),
                legacy: legacyOutputPreset,
                isAvailable: { $0.isAvailable }
            )
        }
        set {
            let qualityPercent = screenshotOutputQualityPercent
            if defaults.object(forKey: "screenshotOutputQualityPercent") == nil {
                defaults.set(qualityPercent, forKey: "screenshotOutputQualityPercent")
            }
            defaults.set(newValue.rawValue, forKey: "screenshotOutputFormat")
            writeLegacyOutputPreset(format: newValue, qualityPercent: qualityPercent)
            screenshotFormat = newValue == .png ? .png : .jpeg
        }
    }

    public var screenshotOutputQualityPercent: Int {
        get {
            guard let stored = defaults.object(forKey: "screenshotOutputQualityPercent") as? Int else {
                return legacyOutputPreset?.qualityPercent ?? Self.defaultOutputQualityPercent
            }
            return Self.clampedQualityPercent(stored)
        }
        set {
            let qualityPercent = Self.clampedQualityPercent(newValue)
            defaults.set(qualityPercent, forKey: "screenshotOutputQualityPercent")
            writeLegacyOutputPreset(
                format: screenshotOutputFormat,
                qualityPercent: qualityPercent
            )
        }
    }

    public var screenshotOutputOptions: ScreenshotOutputOptions {
        ScreenshotOutputOptions(
            format: screenshotOutputFormat,
            quality: Double(screenshotOutputQualityPercent) / 100
        )
    }

    /// Never returns a format this Mac cannot encode, so the setting can't silently
    /// produce bytes that disagree with the file's extension.
    static func resolvedOutputFormat(
        stored: String?,
        legacy: ScreenshotOutputPreset?,
        isAvailable: (ScreenshotOutputFormat) -> Bool
    ) -> ScreenshotOutputFormat {
        if let stored {
            guard let value = ScreenshotOutputFormat(rawValue: stored), isAvailable(value) else {
                return .png
            }
            return value
        }
        let migrated = legacy?.outputFormat ?? .png
        return isAvailable(migrated) ? migrated : .png
    }

    private static let defaultOutputQualityPercent = 85

    private static func clampedQualityPercent(_ value: Int) -> Int {
        min(
            max(value, ScreenshotOutputFormat.qualityPercentRange.lowerBound),
            ScreenshotOutputFormat.qualityPercentRange.upperBound
        )
    }

    private static func downgradeOutputPreset(
        format: ScreenshotOutputFormat,
        qualityPercent: Int
    ) -> ScreenshotOutputPreset {
        guard format != .png else { return .losslessPNG }
        return qualityPercent < standardJPEGDowngradeQualityThreshold
            ? .compactJPEG
            : .standardJPEG
    }

    /// The midpoint between the two lossy presets supported by 1.0.1 and earlier.
    private static let standardJPEGDowngradeQualityThreshold = (
        ScreenshotOutputPreset.compactJPEG.qualityPercent
            + ScreenshotOutputPreset.standardJPEG.qualityPercent
            + 1
    ) / 2

    private func writeLegacyOutputPreset(
        format: ScreenshotOutputFormat,
        qualityPercent: Int
    ) {
        defaults.set(
            Self.downgradeOutputPreset(format: format, qualityPercent: qualityPercent).rawValue,
            forKey: "screenshotOutputPreset"
        )
    }

    /// Defaults written by 1.0.1 and earlier, also maintained as a downgrade projection.
    private var legacyOutputPreset: ScreenshotOutputPreset? {
        if let raw = defaults.string(forKey: "screenshotOutputPreset"),
           let preset = ScreenshotOutputPreset(rawValue: raw) {
            return preset
        }
        return screenshotFormat == .jpeg ? .standardJPEG : nil
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

    /// When `true`, show a KeyCastr-style keystroke overlay while recording.
    /// Opt-in (default off). Requires Input Monitoring permission.
    public var showKeyPressesWhileRecording: Bool {
        get { defaults.object(forKey: "showKeyPressesWhileRecording") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showKeyPressesWhileRecording") }
    }

    /// Last dragged offset of the key-press overlay from the recording frame origin
    /// (AppKit bottom-left). `nil` means default bottom-leading placement inside the capture.
    public var keyPressOverlayOffsetX: Double? {
        get {
            guard defaults.object(forKey: "keyPressOverlayOffsetX") != nil else { return nil }
            return defaults.double(forKey: "keyPressOverlayOffsetX")
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "keyPressOverlayOffsetX")
            } else {
                defaults.removeObject(forKey: "keyPressOverlayOffsetX")
            }
        }
    }

    public var keyPressOverlayOffsetY: Double? {
        get {
            guard defaults.object(forKey: "keyPressOverlayOffsetY") != nil else { return nil }
            return defaults.double(forKey: "keyPressOverlayOffsetY")
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "keyPressOverlayOffsetY")
            } else {
                defaults.removeObject(forKey: "keyPressOverlayOffsetY")
            }
        }
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

    public var lastRecordingArea: StoredCaptureSelection? {
        get {
            guard let data = defaults.data(forKey: "lastRecordingArea"),
                  let value = try? JSONDecoder().decode(StoredCaptureSelection.self, from: data) else {
                return nil
            }
            return value
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "lastRecordingArea")
            } else {
                defaults.removeObject(forKey: "lastRecordingArea")
            }
        }
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

    /// When `true`, the camera PiP becomes nearly transparent while the pointer is over it
    /// (so content behind it is readable without moving the window). Idle stays fully solid.
    /// Presentation / fullscreen mode always stays opaque. Off by default.
    /// Recorded output matches on-screen opacity.
    public var cameraPiPFadeOnHover: Bool {
        get { defaults.object(forKey: "cameraPiPFadeOnHover") as? Bool ?? false }
        set {
            guard cameraPiPFadeOnHover != newValue else { return }
            defaults.set(newValue, forKey: "cameraPiPFadeOnHover")
            NotificationCenter.default.post(name: .cameraPiPHoverOptionsChanged, object: self)
        }
    }

    /// When `true`, mouse clicks pass through the small camera PiP to whatever is behind it
    /// while the pointer is over it. Independent of fade-on-hover. Off by default.
    /// Never applies in fullscreen / presentation mode (PiP stays interactive there).
    public var cameraPiPClickThrough: Bool {
        get { defaults.object(forKey: "cameraPiPClickThrough") as? Bool ?? false }
        set {
            guard cameraPiPClickThrough != newValue else { return }
            defaults.set(newValue, forKey: "cameraPiPClickThrough")
            NotificationCenter.default.post(name: .cameraPiPHoverOptionsChanged, object: self)
        }
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

    public var screenshotClipboardFormat: ScreenshotClipboardFormat {
        get {
            guard let raw = defaults.string(forKey: "screenshotClipboardFormat"),
                  let value = ScreenshotClipboardFormat(rawValue: raw) else { return .png }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: "screenshotClipboardFormat") }
    }

    public var screenshotClipboardContent: ScreenshotClipboardContent {
        get {
            guard let raw = defaults.string(forKey: "screenshotClipboardContent"),
                  let value = ScreenshotClipboardContent(rawValue: raw) else { return .image }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: "screenshotClipboardContent") }
    }

    public var screenshotAutoSave: Bool {
        get { defaults.object(forKey: "screenshotAutoSave") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "screenshotAutoSave") }
    }

    public var screenshotMonthlyFolders: Bool {
        get { defaults.object(forKey: "screenshotMonthlyFolders") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "screenshotMonthlyFolders") }
    }

    public var screenshotFilenameTemplate: String {
        get {
            let raw = defaults.string(forKey: "screenshotFilenameTemplate") ?? FileNaming.defaultScreenshotTemplate
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? FileNaming.defaultScreenshotTemplate
                : raw
        }
        set { defaults.set(newValue, forKey: "screenshotFilenameTemplate") }
    }

    public var screenshotShowsCursor: Bool {
        get { defaults.object(forKey: "screenshotShowsCursor") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "screenshotShowsCursor") }
    }

    public var screenshotTimestampEnabled: Bool {
        get { defaults.object(forKey: "screenshotTimestampEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "screenshotTimestampEnabled") }
    }

    public var screenshotTimestampPosition: ScreenshotTimestampPosition {
        get {
            guard let raw = defaults.string(forKey: "screenshotTimestampPosition"),
                  let value = ScreenshotTimestampPosition(rawValue: raw) else { return .bottomRight }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: "screenshotTimestampPosition") }
    }

    public var screenshotTimestampFormat: ScreenshotTimestampFormat {
        get {
            guard let raw = defaults.string(forKey: "screenshotTimestampFormat"),
                  let value = ScreenshotTimestampFormat(rawValue: raw) else { return .dateTime }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: "screenshotTimestampFormat") }
    }

    public var screenshotTimestampColorHex: String {
        get {
            let raw = defaults.string(forKey: "screenshotTimestampColorHex") ?? "#FFFFFF"
            return ScreenshotTimestampOptions.normalizedColorHex(raw) ?? "#FFFFFF"
        }
        set {
            let normalized = ScreenshotTimestampOptions.normalizedColorHex(newValue) ?? "#FFFFFF"
            defaults.set(normalized, forKey: "screenshotTimestampColorHex")
        }
    }

    public var screenshotTimestampFontSize: Int {
        get {
            let raw = defaults.object(forKey: "screenshotTimestampFontSize") as? Int ?? 14
            return min(
                max(raw, ScreenshotTimestampOptions.fontSizeRange.lowerBound),
                ScreenshotTimestampOptions.fontSizeRange.upperBound
            )
        }
        set {
            let clamped = min(
                max(newValue, ScreenshotTimestampOptions.fontSizeRange.lowerBound),
                ScreenshotTimestampOptions.fontSizeRange.upperBound
            )
            defaults.set(clamped, forKey: "screenshotTimestampFontSize")
        }
    }

    public var screenshotTimestampOptions: ScreenshotTimestampOptions {
        ScreenshotTimestampOptions(
            isEnabled: screenshotTimestampEnabled,
            position: screenshotTimestampPosition,
            format: screenshotTimestampFormat,
            colorHex: screenshotTimestampColorHex,
            fontSize: screenshotTimestampFontSize
        )
    }

    public var captureWindowShadow: Bool {
        get { defaults.object(forKey: "captureWindowShadow") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "captureWindowShadow") }
    }

    public var showMagnifier: Bool {
        get { defaults.object(forKey: "showMagnifier") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showMagnifier") }
    }

    public var lastCaptureSelection: StoredCaptureSelection? {
        get {
            guard let data = defaults.data(forKey: "lastCaptureSelection"),
                  let value = try? JSONDecoder().decode(StoredCaptureSelection.self, from: data) else {
                return nil
            }
            return value
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "lastCaptureSelection")
            } else {
                defaults.removeObject(forKey: "lastCaptureSelection")
            }
        }
    }

    // MARK: Self-Timer

    /// Allowed range for the self-timer duration in seconds. Anything stored
    /// outside this range is clamped on read so the UI / countdown loop
    /// never has to defend against zero or absurd values.
    public static let selfTimerDurationRange: ClosedRange<Int> = 1...60

    /// Default countdown duration in seconds. The setter clamps into
    /// `selfTimerDurationRange`. Stored as `Int` (raw seconds) so users can
    /// pick any value in range — the previous 3/5/10 enum values still
    /// round-trip cleanly because they're plain ints.
    public var selfTimerDurationSeconds: Int {
        get {
            let raw = defaults.object(forKey: "selfTimerDuration") as? Int ?? 5
            return min(max(raw, Self.selfTimerDurationRange.lowerBound), Self.selfTimerDurationRange.upperBound)
        }
        set {
            let clamped = min(max(newValue, Self.selfTimerDurationRange.lowerBound), Self.selfTimerDurationRange.upperBound)
            defaults.set(clamped, forKey: "selfTimerDuration")
        }
    }

    /// Play a per-second tick sound during the self-timer countdown.
    /// Independent of `playShutterSound`: some users want the shutter
    /// sound but find the ticking distracting (or vice versa).
    public var selfTimerPlayTickSound: Bool {
        get { defaults.object(forKey: "selfTimerPlayTickSound") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "selfTimerPlayTickSound") }
    }

    /// Last screen position of the Self-Timer HUD. `nil` means "use the
    /// default top-center placement of the active screen". Persisted as
    /// `[Double]` (x, y) — only written when the user drags the HUD.
    public var selfTimerHUDPosition: CGPoint? {
        get {
            guard let arr = defaults.array(forKey: "selfTimerHUDPosition") as? [Double],
                  arr.count == 2 else { return nil }
            return CGPoint(x: arr[0], y: arr[1])
        }
        set {
            if let p = newValue {
                defaults.set([Double(p.x), Double(p.y)], forKey: "selfTimerHUDPosition")
            } else {
                defaults.removeObject(forKey: "selfTimerHUDPosition")
            }
        }
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

    /// Extra key that, with Shift, grows a 1:1 selection from the click center.
    /// Shift itself is not stored and cannot be changed.
    public var squareCenterLockShortcut: SquareCenterLockShortcut {
        get {
            SquareCenterLockShortcut(
                storedKeyCode: defaults.object(forKey: "squareCenterLockKeyCode") as? Int,
                storedDisplayCharacter: defaults.string(forKey: "squareCenterLockDisplayCharacter")
            )
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: "squareCenterLockKeyCode")
            defaults.set(newValue.displayCharacter, forKey: "squareCenterLockDisplayCharacter")
        }
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

    public var translationProvider: TranslationProviderKind {
        get {
            guard let raw = defaults.string(forKey: "translationProvider"),
                  let provider = TranslationProviderKind(rawValue: raw) else { return .apple }
            return provider
        }
        set {
            migrateLegacyTranslationProviderSettingsIfNeeded()
            defaults.set(newValue.rawValue, forKey: "translationProvider")
        }
    }

    public var translationProviderModel: String {
        get {
            migrateLegacyTranslationProviderSettingsIfNeeded()
            return defaults.string(forKey: translationProviderSettingKey("model"))
                ?? translationProvider.defaultModel
        }
        set {
            migrateLegacyTranslationProviderSettingsIfNeeded()
            defaults.set(newValue, forKey: translationProviderSettingKey("model"))
        }
    }

    public var translationProviderEndpoint: String {
        get {
            migrateLegacyTranslationProviderSettingsIfNeeded()
            return defaults.string(forKey: translationProviderSettingKey("endpoint"))
                ?? translationProvider.defaultEndpoint
        }
        set {
            migrateLegacyTranslationProviderSettingsIfNeeded()
            defaults.set(newValue, forKey: translationProviderSettingKey("endpoint"))
        }
    }

    private func translationProviderSettingKey(_ field: String) -> String {
        "translationProvider.\(translationProvider.rawValue).\(field)"
    }

    private func migrateLegacyTranslationProviderSettingsIfNeeded() {
        let migrationKey = "translationProviderSettingsMigrated"
        guard !defaults.bool(forKey: migrationKey) else { return }

        if let model = defaults.string(forKey: "translationProviderModel") {
            defaults.set(model, forKey: translationProviderSettingKey("model"))
        }
        if let endpoint = defaults.string(forKey: "translationProviderEndpoint") {
            defaults.set(endpoint, forKey: translationProviderSettingKey("endpoint"))
        }
        defaults.set(true, forKey: migrationKey)
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

    public func translationAPIKey() -> String? {
        try? KeychainHelper(service: "com.awesomemacapps.capso.translation")
            .get(account: translationProvider.rawValue)
    }

    public func setTranslationAPIKey(_ value: String?) throws {
        let keychain = KeychainHelper(service: "com.awesomemacapps.capso.translation")
        let account = translationProvider.rawValue
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            try keychain.delete(account: account)
        } else {
            try keychain.set(trimmed, account: account)
        }
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

    public var openedImageSaveBehavior: OpenedImageSaveBehavior {
        get {
            guard let raw = defaults.string(forKey: "openedImageSaveBehavior"),
                  let value = OpenedImageSaveBehavior(rawValue: raw) else { return .ask }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: "openedImageSaveBehavior") }
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

    public var cloudShareRegion: String? {
        get { defaults.string(forKey: "cloudShareRegion") }
        set { defaults.set(newValue, forKey: "cloudShareRegion") }
    }

    public var cloudShareEndpoint: String? {
        get { defaults.string(forKey: "cloudShareEndpoint") }
        set { defaults.set(newValue, forKey: "cloudShareEndpoint") }
    }

    public var cloudSharePathPrefix: String? {
        get { defaults.string(forKey: "cloudSharePathPrefix") }
        set { defaults.set(newValue, forKey: "cloudSharePathPrefix") }
    }

    public var cloudShareAutoUploadEnabled: Bool {
        get { defaults.object(forKey: "cloudShareAutoUploadEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "cloudShareAutoUploadEnabled") }
    }

    public var isCloudShareConfigured: Bool {
        guard
            let provider = cloudShareProvider,
            cloudShareURLPrefix != nil,
            cloudShareBucket != nil
        else {
            return false
        }

        switch provider {
        case "r2":
            return cloudShareAccountID != nil
        case "s3", "tencentCOS", "aliyunOSS":
            return cloudShareRegion != nil
        default:
            return false
        }
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

// MARK: - Camera PiP hover option notifications

public extension Notification.Name {
    /// Posted when `cameraPiPFadeOnHover` or `cameraPiPClickThrough` changes,
    /// so a live PiP can re-apply opacity / click-through without observing all UserDefaults writes.
    static let cameraPiPHoverOptionsChanged = Notification.Name("cameraPiPHoverOptionsChanged")
}
