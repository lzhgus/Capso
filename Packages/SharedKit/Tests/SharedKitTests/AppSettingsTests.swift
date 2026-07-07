import Foundation
import Testing
@testable import SharedKit

@Suite("AppSettings")
struct AppSettingsTests {
    @Test("Default export location is Desktop")
    func defaultExportLocation() {
        let settings = AppSettings()
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        #expect(settings.exportLocation == desktopURL)
    }

    @Test("Default screenshot format is PNG")
    func defaultScreenshotFormat() {
        let settings = AppSettings()
        #expect(settings.screenshotFormat == .png)
    }

    @Test("Default screenshot output preset is lossless PNG")
    func defaultScreenshotOutputPreset() {
        let suite = "test.screenshotOutputPreset.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)

        #expect(settings.screenshotOutputPreset == .losslessPNG)
        #expect(settings.screenshotOutputPreset.fileFormat == .png)
        #expect(settings.screenshotOutputPreset.jpegQuality == nil)
    }

    @Test("Screenshot output presets expose JPEG quality")
    func screenshotOutputPresetJPEGQuality() {
        #expect(ScreenshotOutputPreset.standardJPEG.fileFormat == .jpeg)
        #expect(ScreenshotOutputPreset.standardJPEG.jpegQuality == 0.85)
        #expect(ScreenshotOutputPreset.compactJPEG.fileFormat == .jpeg)
        #expect(ScreenshotOutputPreset.compactJPEG.jpegQuality == 0.70)
    }

    @Test("Screenshot output preset falls back to legacy JPEG format")
    func screenshotOutputPresetLegacyFormatFallback() {
        let suite = "test.screenshotOutputPreset.legacy"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)

        settings.screenshotFormat = .jpeg

        #expect(settings.screenshotOutputPreset == .standardJPEG)
    }

    @Test("Default screenshot filename template matches FileNaming default")
    func defaultScreenshotFilenameTemplate() {
        let suite = "test.screenshotFilenameTemplate.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)

        #expect(settings.screenshotFilenameTemplate == FileNaming.defaultScreenshotTemplate)
    }

    @Test("Screenshot filename template persists")
    func screenshotFilenameTemplatePersists() {
        let suite = "test.screenshotFilenameTemplate.persist"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = AppSettings(defaults: defaults)
        first.screenshotFilenameTemplate = "{date}-{time}"

        let second = AppSettings(defaults: defaults)
        #expect(second.screenshotFilenameTemplate == "{date}-{time}")
    }

    @Test("Monthly screenshot folders are disabled by default")
    func defaultScreenshotMonthlyFolders() {
        let suite = "test.screenshotMonthlyFolders.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)

        #expect(settings.screenshotMonthlyFolders == false)
    }

    @Test("Screenshot cursor capture is disabled by default")
    func defaultScreenshotShowsCursor() {
        let suite = "test.screenshotShowsCursor.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.screenshotShowsCursor == false)
    }

    @Test("Screenshot cursor capture persists across instances")
    func screenshotShowsCursorPersists() {
        let suite = "test.screenshotShowsCursor.persists"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        first.screenshotShowsCursor = true
        let second = AppSettings(defaults: defaults)
        #expect(second.screenshotShowsCursor == true)
    }

    @Test("Screenshot timestamp defaults are opt-in")
    func screenshotTimestampDefaultsAreOptIn() {
        let suite = "test.screenshotTimestamp.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)

        #expect(settings.screenshotTimestampEnabled == false)
        #expect(settings.screenshotTimestampPosition == .bottomRight)
        #expect(settings.screenshotTimestampFormat == .dateTime)
        #expect(settings.screenshotTimestampColorHex == "#FFFFFF")
        #expect(settings.screenshotTimestampFontSize == 14)
    }

    @Test("Screenshot timestamp settings persist")
    func screenshotTimestampSettingsPersist() {
        let suite = "test.screenshotTimestamp.persist"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)

        first.screenshotTimestampEnabled = true
        first.screenshotTimestampPosition = .topLeft
        first.screenshotTimestampFormat = .iso8601
        first.screenshotTimestampColorHex = "#112233"
        first.screenshotTimestampFontSize = 22

        let second = AppSettings(defaults: defaults)
        #expect(second.screenshotTimestampEnabled == true)
        #expect(second.screenshotTimestampPosition == .topLeft)
        #expect(second.screenshotTimestampFormat == .iso8601)
        #expect(second.screenshotTimestampColorHex == "#112233")
        #expect(second.screenshotTimestampFontSize == 22)
    }

    @Test("Default Quick Access position is bottomLeft")
    func defaultQuickAccessPosition() {
        let settings = AppSettings()
        #expect(settings.quickAccessPosition == .bottomLeft)
    }

    @Test("Default shutter sound is enabled")
    func defaultShutterSound() {
        let settings = AppSettings()
        #expect(settings.playShutterSound == true)
    }

    @Test("Diagnostic logging is disabled by default")
    func defaultDiagnosticLoggingEnabled() {
        let suite = "test.diagnosticLogging.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.diagnosticLoggingEnabled == false)
    }

    @Test("Diagnostic logging preference persists across instances")
    func diagnosticLoggingPersists() {
        let suite = "test.diagnosticLogging.persists"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        first.diagnosticLoggingEnabled = true
        let second = AppSettings(defaults: defaults)
        #expect(second.diagnosticLoggingEnabled == true)
    }

    @Test("Menu bar icon is shown by default")
    func defaultShowMenuBarIcon() {
        let suite = "test.showMenuBarIcon.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.showMenuBarIcon == true)
    }

    @Test("Hiding the menu bar icon persists across instances")
    func showMenuBarIconPersists() {
        let suite = "test.showMenuBarIcon.persists"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        first.showMenuBarIcon = false
        let second = AppSettings(defaults: defaults)
        #expect(second.showMenuBarIcon == false)
    }

    @Test("Default auto-close interval is 5 seconds")
    func defaultAutoCloseInterval() {
        let settings = AppSettings()
        #expect(settings.quickAccessAutoCloseInterval == 5)
    }

    @Test("Pro features locked by default")
    func proFeaturesLockedByDefault() {
        let settings = AppSettings()
        #expect(settings.isProUnlocked == false)
    }

    @Test("Translation provider defaults to Apple")
    func translationProviderDefaultsToApple() {
        let suite = "test.translationProvider.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)

        #expect(settings.translationProvider == .apple)
    }

    @Test("Translation provider choices exclude DeepSeek")
    func translationProviderChoicesExcludeDeepSeek() {
        #expect(TranslationProviderKind.allCases.map(\.rawValue) == [
            "apple",
            "openAICompatible",
            "deepL",
            "custom",
        ])
    }

    @Test("Translation provider settings persist across instances")
    func translationProviderSettingsPersist() {
        let suite = "test.translationProvider.persist"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)

        first.translationProvider = .openAICompatible
        first.translationProviderModel = "gpt-4o-mini"
        first.translationProviderEndpoint = "https://example.com/chat/completions"

        let second = AppSettings(defaults: defaults)
        #expect(second.translationProvider == .openAICompatible)
        #expect(second.translationProviderModel == "gpt-4o-mini")
        #expect(second.translationProviderEndpoint == "https://example.com/chat/completions")
    }

    @Test("File formats map common extensions")
    func fileFormatExtensionMapping() {
        #expect(FileFormat(pathExtension: "png") == .png)
        #expect(FileFormat(pathExtension: "jpg") == .jpeg)
        #expect(FileFormat(pathExtension: "jpeg") == .jpeg)
        #expect(FileFormat(pathExtension: "gif") == .gif)
        #expect(FileFormat(pathExtension: "mp4") == .mp4)
        #expect(FileFormat(pathExtension: "mov") == .mov)
        #expect(FileFormat(pathExtension: "webm") == nil)
    }

    @Test("Generated file names preserve the requested extension")
    func generatedFileNamesUseFormatExtension() {
        let date = Date(timeIntervalSince1970: 0)

        #expect(
            FileNaming.generateFileName(for: .screenshot, format: .png, date: date).hasSuffix(".png")
        )
        #expect(
            FileNaming.generateFileName(for: .recording, format: .gif, date: date).hasSuffix(".gif")
        )
        #expect(
            FileNaming.generateFileName(for: .recording, format: .mov, date: date).hasSuffix(".mov")
        )
    }

    @Test("Default translation target language is non-empty")
    func defaultTranslationTargetLanguage() {
        let settings = AppSettings()
        #expect(!settings.translationTargetLanguage.isEmpty)
    }

    @Test("Default translationAutoCopy is true")
    func defaultTranslationAutoCopy() {
        let suite = "test.translationAutoCopy.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.translationAutoCopy == true)
    }

    @Test("Default translationShowOriginal is true")
    func defaultTranslationShowOriginal() {
        let suite = "test.translationShowOriginal.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.translationShowOriginal == true)
    }

    @Test("Default card position is .centerScreen")
    func defaultCardPosition() {
        let suite = "test.translationCardPosition.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.translationCardPosition == .centerScreen)
    }

    @Test("Default auto-dismiss is .manual")
    func defaultAutoDismiss() {
        let suite = "test.translationAutoDismiss.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.translationAutoDismiss == .manual)
    }

    @Test("Translation onboarding flag defaults false")
    func defaultOnboardingShown() {
        let suite = "test.translationOnboardingShown.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.translationOnboardingShown == false)
    }

    @Test("Default auto-dismiss delay is 10 seconds")
    func defaultAutoDismissDelay() {
        let suite = "test.translationAutoDismissDelay.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.translationAutoDismissDelay == 10)
    }

    @Test("Cloud Share configuration supports provider-specific fields")
    func cloudShareProviderFieldsPersist() {
        let suite = "test.cloudShare.providerFields"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)

        first.cloudShareProvider = "s3"
        first.cloudShareURLPrefix = "https://cdn.example.com"
        first.cloudShareBucket = "capso"
        first.cloudShareRegion = "us-east-1"
        first.cloudShareEndpoint = "https://s3.us-east-1.amazonaws.com"
        first.cloudSharePathPrefix = "screenshots"

        let second = AppSettings(defaults: defaults)
        #expect(second.isCloudShareConfigured == true)
        #expect(second.cloudShareRegion == "us-east-1")
        #expect(second.cloudShareEndpoint == "https://s3.us-east-1.amazonaws.com")
        #expect(second.cloudSharePathPrefix == "screenshots")
    }

    @Test("Cloud Share R2 configuration remains compatible with account ID")
    func cloudShareR2Compatibility() {
        let suite = "test.cloudShare.r2Compatibility"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)

        settings.cloudShareProvider = "r2"
        settings.cloudShareURLPrefix = "https://pub.example.com"
        settings.cloudShareBucket = "capso"
        settings.cloudShareAccountID = "abc123"

        #expect(settings.isCloudShareConfigured == true)
        #expect(settings.cloudShareAccountID == "abc123")
    }

    // MARK: Self-Timer

    @Test("Default self-timer duration is 5 seconds")
    func defaultSelfTimerDuration() {
        let suite = "test.selfTimerDuration.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.selfTimerDurationSeconds == 5)
    }

    @Test("Self-timer duration persists across instances")
    func selfTimerDurationPersists() {
        let suite = "test.selfTimerDuration.persists"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        first.selfTimerDurationSeconds = 7
        let second = AppSettings(defaults: defaults)
        #expect(second.selfTimerDurationSeconds == 7)
    }

    @Test("Self-timer duration clamps below the lower bound")
    func selfTimerDurationClampsLow() {
        let suite = "test.selfTimerDuration.clampLow"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        settings.selfTimerDurationSeconds = 0
        #expect(settings.selfTimerDurationSeconds == AppSettings.selfTimerDurationRange.lowerBound)
        settings.selfTimerDurationSeconds = -10
        #expect(settings.selfTimerDurationSeconds == AppSettings.selfTimerDurationRange.lowerBound)
    }

    @Test("Self-timer duration clamps above the upper bound")
    func selfTimerDurationClampsHigh() {
        let suite = "test.selfTimerDuration.clampHigh"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        settings.selfTimerDurationSeconds = 1000
        #expect(settings.selfTimerDurationSeconds == AppSettings.selfTimerDurationRange.upperBound)
    }

    @Test("Tick sound defaults to enabled")
    func defaultSelfTimerTickSound() {
        let suite = "test.selfTimerPlayTickSound.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.selfTimerPlayTickSound == true)
    }

    @Test("Tick sound persists when disabled")
    func selfTimerTickSoundPersists() {
        let suite = "test.selfTimerPlayTickSound.persists"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        first.selfTimerPlayTickSound = false
        let second = AppSettings(defaults: defaults)
        #expect(second.selfTimerPlayTickSound == false)
    }

    @Test("Last recording area persists across instances")
    func lastRecordingAreaPersists() {
        let suite = "test.lastRecordingArea.persists"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        let selection = StoredCaptureSelection.area(
            rect: CGRect(x: 24, y: 48, width: 640, height: 360),
            screenID: 42
        )
        first.lastRecordingArea = selection
        let second = AppSettings(defaults: defaults)
        #expect(second.lastRecordingArea == selection)
    }

    @Test("Self-timer HUD position defaults to nil")
    func defaultSelfTimerHUDPosition() {
        let suite = "test.selfTimerHUDPosition.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.selfTimerHUDPosition == nil)
    }

    @Test("Self-timer HUD position round-trips and clears")
    func selfTimerHUDPositionRoundTrip() {
        let suite = "test.selfTimerHUDPosition.roundtrip"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        settings.selfTimerHUDPosition = CGPoint(x: 412.5, y: 88.0)
        #expect(settings.selfTimerHUDPosition == CGPoint(x: 412.5, y: 88.0))
        settings.selfTimerHUDPosition = nil
        #expect(settings.selfTimerHUDPosition == nil)
    }
}
