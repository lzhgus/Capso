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
