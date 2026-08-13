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

    @Test("Screenshot output defaults to lossless PNG at 85% quality")
    func defaultScreenshotOutput() {
        let settings = makeSettings("test.screenshotOutput.default")

        #expect(settings.screenshotOutputFormat == .png)
        #expect(settings.screenshotOutputQualityPercent == 85)
        #expect(settings.screenshotOutputOptions == ScreenshotOutputOptions(format: .png, quality: 0.85))
    }

    @Test("Screenshot output format and quality persist")
    func screenshotOutputPersists() {
        let suite = "test.screenshotOutput.persist"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = AppSettings(defaults: defaults)
        first.screenshotOutputFormat = .jpeg
        first.screenshotOutputQualityPercent = 60

        let second = AppSettings(defaults: defaults)
        #expect(second.screenshotOutputFormat == .jpeg)
        #expect(second.screenshotOutputQualityPercent == 60)
        #expect(second.screenshotOutputOptions.quality == 0.6)
    }

    @Test("Screenshot output migrates from the legacy preset", arguments: [
        (ScreenshotOutputPreset.losslessPNG, ScreenshotOutputFormat.png, 85),
        (.standardJPEG, .jpeg, 85),
        (.compactJPEG, .jpeg, 70),
    ])
    func screenshotOutputMigratesFromPreset(
        preset: ScreenshotOutputPreset,
        format: ScreenshotOutputFormat,
        percent: Int
    ) {
        let suite = "test.screenshotOutput.migrate.\(preset.rawValue)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(preset.rawValue, forKey: "screenshotOutputPreset")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.screenshotOutputFormat == format)
        #expect(settings.screenshotOutputQualityPercent == percent)
    }

    @Test("Screenshot output quality clamps to the supported range")
    func screenshotOutputQualityClamps() {
        let settings = makeSettings("test.screenshotOutput.clamp")

        settings.screenshotOutputQualityPercent = 0
        #expect(settings.screenshotOutputQualityPercent == ScreenshotOutputFormat.qualityPercentRange.lowerBound)

        settings.screenshotOutputQualityPercent = 500
        #expect(settings.screenshotOutputQualityPercent == ScreenshotOutputFormat.qualityPercentRange.upperBound)
    }

    @Test("Screenshot output format ignores an unrecognized stored value")
    func screenshotOutputFormatIgnoresUnknownValue() {
        let suite = "test.screenshotOutput.unknown"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set("webp", forKey: "screenshotOutputFormat")

        #expect(AppSettings(defaults: defaults).screenshotOutputFormat == .png)
    }

    @Test("Screenshot output format falls back to PNG when the codec is unavailable")
    func screenshotOutputFormatRejectsUnavailableCodec() {
        let resolved = AppSettings.resolvedOutputFormat(
            stored: "heic",
            legacy: nil,
            isAvailable: { $0 != .heic }
        )

        #expect(resolved == .png)
    }

    @Test("An unavailable stored format does not revive a legacy preset")
    func screenshotOutputFormatRejectsUnavailableCodecBeforeLegacyFallback() {
        let resolved = AppSettings.resolvedOutputFormat(
            stored: "heic",
            legacy: .standardJPEG,
            isAvailable: { $0 != .heic }
        )

        #expect(resolved == .png)
    }

    @Test("Screenshot output format honours an available stored codec")
    func screenshotOutputFormatHonoursAvailableCodec() {
        let resolved = AppSettings.resolvedOutputFormat(
            stored: "heic",
            legacy: nil,
            isAvailable: { _ in true }
        )

        #expect(resolved == .heic)
    }

    @Test("Screenshot output format falls back to PNG when a migrated codec is unavailable")
    func screenshotOutputFormatRejectsUnavailableMigratedCodec() {
        let resolved = AppSettings.resolvedOutputFormat(
            stored: nil,
            legacy: .standardJPEG,
            isAvailable: { $0 != .jpeg }
        )

        #expect(resolved == .png)
    }

    @Test("Setting the screenshot output format keeps the legacy format key in sync")
    func screenshotOutputFormatWritesLegacyKey() {
        let settings = makeSettings("test.screenshotOutput.legacyWriteBack")

        settings.screenshotOutputFormat = .heic
        #expect(settings.screenshotFormat == .jpeg)

        settings.screenshotOutputFormat = .png
        #expect(settings.screenshotFormat == .png)
    }

    @Test("Changing the screenshot output format replaces a stale legacy preset")
    func screenshotOutputFormatReplacesLegacyPreset() {
        let suite = "test.screenshotOutput.legacyPresetWriteBack"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(ScreenshotOutputPreset.compactJPEG.rawValue, forKey: "screenshotOutputPreset")
        let settings = AppSettings(defaults: defaults)

        settings.screenshotOutputFormat = .png

        #expect(defaults.string(forKey: "screenshotOutputPreset") == ScreenshotOutputPreset.losslessPNG.rawValue)
        #expect(settings.screenshotFormat == .png)
    }

    @Test("Changing the screenshot output format preserves migrated quality")
    func screenshotOutputFormatPreservesMigratedQuality() {
        let suite = "test.screenshotOutput.migratedQualityWriteBack"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(ScreenshotOutputPreset.compactJPEG.rawValue, forKey: "screenshotOutputPreset")
        let settings = AppSettings(defaults: defaults)

        settings.screenshotOutputFormat = .png

        #expect(settings.screenshotOutputQualityPercent == 70)
        #expect(defaults.object(forKey: "screenshotOutputQualityPercent") as? Int == 70)
    }

    @Test("Changing screenshot quality keeps the legacy preset in sync")
    func screenshotOutputQualityWritesLegacyPreset() {
        let suite = "test.screenshotOutput.legacyQualityWriteBack"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        settings.screenshotOutputFormat = .jpeg

        settings.screenshotOutputQualityPercent = 70
        #expect(defaults.string(forKey: "screenshotOutputPreset") == ScreenshotOutputPreset.compactJPEG.rawValue)

        settings.screenshotOutputQualityPercent = 85
        #expect(defaults.string(forKey: "screenshotOutputPreset") == ScreenshotOutputPreset.standardJPEG.rawValue)
    }

    @Test("Legacy preset quality projection changes at the midpoint")
    func screenshotOutputQualityUsesNearestLegacyPreset() {
        let suite = "test.screenshotOutput.legacyQualityBoundary"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        settings.screenshotOutputFormat = .jpeg

        settings.screenshotOutputQualityPercent = 77
        #expect(defaults.string(forKey: "screenshotOutputPreset") == ScreenshotOutputPreset.compactJPEG.rawValue)

        settings.screenshotOutputQualityPercent = 78
        #expect(defaults.string(forKey: "screenshotOutputPreset") == ScreenshotOutputPreset.standardJPEG.rawValue)
    }

    private func makeSettings(_ suite: String) -> AppSettings {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppSettings(defaults: defaults)
    }

    @Test("Screenshot clipboard format defaults to PNG and persists")
    func screenshotClipboardFormatDefaultsAndPersists() {
        let suite = "test.screenshotClipboardFormat"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = AppSettings(defaults: defaults)
        #expect(first.screenshotClipboardFormat == .png)

        first.screenshotClipboardFormat = .jpeg

        let second = AppSettings(defaults: defaults)
        #expect(second.screenshotClipboardFormat == .jpeg)
    }

    @Test("Screenshot clipboard content defaults to image and persists file path")
    func screenshotClipboardContentDefaultsAndPersists() {
        let suite = "test.screenshotClipboardContent"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = AppSettings(defaults: defaults)
        #expect(first.screenshotClipboardContent == .image)

        first.screenshotClipboardContent = .filePath

        let second = AppSettings(defaults: defaults)
        #expect(second.screenshotClipboardContent == .filePath)
    }

    @Test("Screenshot output format falls back to the legacy JPEG format key")
    func screenshotOutputFormatLegacyFallback() {
        let settings = makeSettings("test.screenshotOutput.legacyRead")

        settings.screenshotFormat = .jpeg

        #expect(settings.screenshotOutputFormat == .jpeg)
        #expect(settings.screenshotOutputQualityPercent == 85)
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

    @Test("Center-screen Quick Access position persists across instances")
    func centerScreenQuickAccessPositionPersists() {
        let suite = "test.quickAccessPosition.centerScreen"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)

        first.quickAccessPosition = .centerScreen

        let second = AppSettings(defaults: defaults)
        #expect(second.quickAccessPosition == .centerScreen)
    }

    @Test("Default shutter sound is enabled")
    func defaultShutterSound() {
        let settings = AppSettings()
        #expect(settings.playShutterSound == true)
    }

    @Test("Show key presses while recording is disabled by default")
    func defaultShowKeyPressesWhileRecording() {
        let suite = "test.showKeyPressesWhileRecording.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.showKeyPressesWhileRecording == false)
    }

    @Test("Show key presses while recording persists across instances")
    func showKeyPressesWhileRecordingPersists() {
        let suite = "test.showKeyPressesWhileRecording.persists"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        first.showKeyPressesWhileRecording = true
        let second = AppSettings(defaults: defaults)
        #expect(second.showKeyPressesWhileRecording == true)
    }

    @Test("Camera PiP fade on hover is disabled by default")
    func defaultCameraPiPFadeOnHover() {
        let suite = "test.cameraPiPFadeOnHover.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.cameraPiPFadeOnHover == false)
    }

    @Test("Camera PiP fade on hover persists across instances")
    func cameraPiPFadeOnHoverPersists() {
        let suite = "test.cameraPiPFadeOnHover.persists"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        first.cameraPiPFadeOnHover = true
        let second = AppSettings(defaults: defaults)
        #expect(second.cameraPiPFadeOnHover == true)
    }

    @Test("Camera PiP hover option changes post a scoped notification only when value changes")
    func cameraPiPHoverOptionsChangedNotification() {
        let suite = "test.cameraPiPHoverOptionsChanged.notification"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)

        final class PostCounter: @unchecked Sendable {
            var count = 0
        }
        let posts = PostCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .cameraPiPHoverOptionsChanged,
            object: settings,
            queue: nil
        ) { _ in posts.count += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        settings.cameraPiPFadeOnHover = true
        settings.cameraPiPFadeOnHover = true // no-op, same value
        #expect(posts.count == 1)

        settings.cameraPiPClickThrough = true
        settings.cameraPiPClickThrough = true // no-op
        #expect(posts.count == 2)
    }

    @Test("Camera PiP click-through is disabled by default")
    func defaultCameraPiPClickThrough() {
        let suite = "test.cameraPiPClickThrough.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.cameraPiPClickThrough == false)
    }

    @Test("Camera PiP click-through persists across instances")
    func cameraPiPClickThroughPersists() {
        let suite = "test.cameraPiPClickThrough.persists"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        first.cameraPiPClickThrough = true
        let second = AppSettings(defaults: defaults)
        #expect(second.cameraPiPClickThrough == true)
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

    @Test("Automation URLs are disabled by default")
    func defaultAutomationURLsEnabled() {
        let suite = "test.automationURLs.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.automationURLsEnabled == false)
    }

    @Test("Automation URL preference persists across instances")
    func automationURLsEnabledPersists() {
        let suite = "test.automationURLs.persists"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)
        first.automationURLsEnabled = true
        let second = AppSettings(defaults: defaults)
        #expect(second.automationURLsEnabled == true)
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
        #expect(FileFormat(pathExtension: "heic") == .heic)
        #expect(FileFormat(pathExtension: "HEIC") == .heic)
        #expect(FileFormat(pathExtension: "heif") == .heic)
        #expect(FileFormat(pathExtension: "webm") == nil)
        #expect(FileFormat(pathExtension: "webp") == nil)
    }

    @Test("HEIC maps to the public.heic content type")
    func heicContentType() {
        #expect(FileFormat.heic.contentType == .heic)
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
        #expect(
            FileNaming.generateFileName(for: .screenshot, format: .heic, date: date).hasSuffix(".heic")
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

    @Test("Cloud Share automatic upload is opt-in and persists")
    func cloudShareAutoUploadPreference() {
        let suite = "test.cloudShare.autoUpload"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppSettings(defaults: defaults)

        #expect(first.cloudShareAutoUploadEnabled == false)

        first.cloudShareAutoUploadEnabled = true

        let second = AppSettings(defaults: defaults)
        #expect(second.cloudShareAutoUploadEnabled == true)
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

    @Test("Default opened image save behavior is ask")
    func defaultOpenedImageSaveBehavior() {
        let suite = "test.openedImageSaveBehavior.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)

        #expect(settings.openedImageSaveBehavior == .ask)
    }

    @Test("Opened image save behavior round-trips")
    func openedImageSaveBehaviorRoundTrip() {
        let suite = "test.openedImageSaveBehavior.roundtrip"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)

        settings.openedImageSaveBehavior = .overwrite
        #expect(settings.openedImageSaveBehavior == .overwrite)

        settings.openedImageSaveBehavior = .copy
        #expect(settings.openedImageSaveBehavior == .copy)
    }

    @Test("Square center-lock shortcut defaults to Shift+C")
    func squareCenterLockShortcutDefaultsToC() {
        let settings = makeSettings("test.squareCenterLock.default")
        #expect(settings.squareCenterLockShortcut == .default)
        #expect(settings.squareCenterLockShortcut.displayCharacter == "C")
    }

    @Test("Square center-lock shortcut persists across AppSettings instances")
    func squareCenterLockShortcutPersists() {
        let suite = "test.squareCenterLock.persist"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = AppSettings(defaults: defaults)
        first.squareCenterLockShortcut = SquareCenterLockShortcut(
            keyCode: 7,
            displayCharacter: "X"
        )

        let second = AppSettings(defaults: defaults)
        #expect(second.squareCenterLockShortcut.keyCode == 7)
        #expect(second.squareCenterLockShortcut.displayCharacter == "X")
    }

    @Test("An invalid stored square center-lock shortcut falls back to C")
    func squareCenterLockShortcutFallsBackWhenInvalid() {
        let suite = "test.squareCenterLock.invalid"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(53, forKey: "squareCenterLockKeyCode")
        defaults.set("C", forKey: "squareCenterLockDisplayCharacter")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.squareCenterLockShortcut == .default)
    }
}
