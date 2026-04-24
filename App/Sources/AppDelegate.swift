// App/Sources/AppDelegate.swift
import AppKit
import SharedKit
import KeyboardShortcuts
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    let settings = AppSettings()
    let permissionManager = PermissionManager()
    private(set) var captureCoordinator: CaptureCoordinator?
    private(set) var recordingCoordinator: RecordingCoordinator?
    private(set) var ocrCoordinator: OCRCoordinator?
    private(set) var translationCoordinator: TranslationCoordinator?
    private(set) var historyCoordinator: HistoryCoordinator?
    private var preferencesWindow: PreferencesWindow?
    /// Sparkle update coordinator used by preferences and manual update checks.
    let updateManager = UpdateManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Show tooltips faster (default is ~2s, reduce to 0.3s)
        UserDefaults.standard.set(300, forKey: "NSInitialToolTipDelay")

        migrateShortcutsIfNeeded()
        settings.startTrial()
        captureCoordinator = CaptureCoordinator(settings: settings)
        recordingCoordinator = RecordingCoordinator(settings: settings)
        ocrCoordinator = OCRCoordinator(settings: settings)
        translationCoordinator = TranslationCoordinator(settings: settings)
        historyCoordinator = HistoryCoordinator(settings: settings)
        captureCoordinator!.ocrCoordinator = ocrCoordinator
        captureCoordinator!.translationCoordinator = translationCoordinator
        captureCoordinator!.historyCoordinator = historyCoordinator
        recordingCoordinator!.historyCoordinator = historyCoordinator
        preferencesWindow = PreferencesWindow(settings: settings, updateManager: updateManager)
        menuBarController = MenuBarController(
            settings: settings,
            captureCoordinator: captureCoordinator!,
            recordingCoordinator: recordingCoordinator!,
            ocrCoordinator: ocrCoordinator!,
            translationCoordinator: translationCoordinator!,
            historyCoordinator: historyCoordinator!,
            onShowPreferences: { [weak self] in self?.showPreferences() }
        )
        registerGlobalShortcuts()
        historyCoordinator?.runCleanup()

        // Safety net: if the menu bar icon is hidden, the user has no obvious
        // way to access settings, so surface Preferences on launch.
        if !settings.showMenuBarIcon {
            DispatchQueue.main.async { [weak self] in
                self?.showPreferences()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openScreenshotSettings,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let tabRaw = (notification.object as? PreferencesTab)?.rawValue
            MainActor.assumeIsolated {
                let tab = tabRaw.flatMap(PreferencesTab.init(rawValue:)) ?? .screenshots
                self?.preferencesWindow?.show(tab: tab)
            }
        }
        Task {
            await permissionManager.checkScreenRecordingPermission()
            // Request camera permission early so the system dialog
            // appears at a normal window level — not behind a recording
            // overlay (which is at .screenSaver level and would hide
            // the dialog, making it impossible to grant).
            await permissionManager.requestCameraPermission()
        }
    }

    /// One-time migration: clear stale KeyboardShortcuts UserDefaults so new defaults apply.
    private func migrateShortcutsIfNeeded() {
        let migrationKey = "shortcutsMigratedToOptionShift"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        KeyboardShortcuts.reset(.captureArea, .captureFullscreen, .captureWindow, .captureText, .recordScreen)
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private func registerGlobalShortcuts() {
        KeyboardShortcuts.onKeyDown(for: .captureArea) { [weak self] in
            self?.captureCoordinator?.captureArea()
        }
        KeyboardShortcuts.onKeyDown(for: .captureFullscreen) { [weak self] in
            self?.captureCoordinator?.captureFullscreen()
        }
        KeyboardShortcuts.onKeyDown(for: .captureWindow) { [weak self] in
            self?.captureCoordinator?.captureWindow()
        }
        KeyboardShortcuts.onKeyDown(for: .captureText) { [weak self] in
            self?.ocrCoordinator?.startInstantOCR()
        }
        KeyboardShortcuts.onKeyDown(for: .recordScreen) { [weak self] in
            self?.recordingCoordinator?.startRecordingFlow()
        }
        KeyboardShortcuts.onKeyDown(for: .captureScrolling) { [weak self] in
            self?.captureCoordinator?.captureScrolling()
        }
        KeyboardShortcuts.onKeyDown(for: .captureAreaToClipboard) { [weak self] in
            self?.captureCoordinator?.captureAreaToClipboard()
        }
        KeyboardShortcuts.onKeyDown(for: .captureAreaAndAnnotate) { [weak self] in
            self?.captureCoordinator?.captureAreaAndAnnotate()
        }
        KeyboardShortcuts.onKeyDown(for: .screenshotHistory) { [weak self] in
            self?.historyCoordinator?.showWindow()
        }
        KeyboardShortcuts.onKeyDown(for: .captureAndTranslate) { [weak self] in
            guard let self else { return }
            // If the user pressed ⌘⇧T while a Quick Access panel has focus
            // (hovered / clicked), translate THAT capture rather than
            // starting a brand-new capture flow. The global hotkey otherwise
            // always wins over the panel's local `.keyboardShortcut`.
            if self.captureCoordinator?.invokeQuickAccessTranslateIfKey() == true {
                return
            }
            self.translationCoordinator?.startCaptureAndTranslate()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Called when the user double-clicks the app while it's already running
    /// (Spotlight, Launchpad, Finder). For an LSUIElement app with the menu
    /// bar icon hidden, this is the user's only way back into Preferences.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !settings.showMenuBarIcon {
            showPreferences()
        }
        return true
    }

    func showPreferences() {
        preferencesWindow?.show()
    }
}
