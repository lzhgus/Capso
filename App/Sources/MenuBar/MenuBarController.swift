// App/Sources/MenuBar/MenuBarController.swift
import AppKit
import SharedKit
import KeyboardShortcuts

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let settings: AppSettings
    private let captureCoordinator: CaptureCoordinator
    private let recordingCoordinator: RecordingCoordinator
    private let ocrCoordinator: OCRCoordinator
    private let onShowPreferences: () -> Void

    init(settings: AppSettings, captureCoordinator: CaptureCoordinator, recordingCoordinator: RecordingCoordinator, ocrCoordinator: OCRCoordinator, onShowPreferences: @escaping () -> Void) {
        self.settings = settings
        self.captureCoordinator = captureCoordinator
        self.recordingCoordinator = recordingCoordinator
        self.ocrCoordinator = ocrCoordinator
        self.onShowPreferences = onShowPreferences
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
        }
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let captureArea = menuItem(String(localized: "Capture Area"), action: #selector(captureArea))
        captureArea.setShortcut(for: .captureArea)
        menu.addItem(captureArea)

        let captureFullscreen = menuItem(String(localized: "Capture Fullscreen"), action: #selector(captureFullscreen))
        captureFullscreen.setShortcut(for: .captureFullscreen)
        menu.addItem(captureFullscreen)

        let captureWindow = menuItem(String(localized: "Capture Window"), action: #selector(captureWindow))
        captureWindow.setShortcut(for: .captureWindow)
        menu.addItem(captureWindow)

        menu.addItem(.separator())

        let captureText = menuItem(String(localized: "Capture Text (OCR)"), action: #selector(captureText))
        captureText.setShortcut(for: .captureText)
        menu.addItem(captureText)

        menu.addItem(.separator())

        let recordScreen = menuItem(String(localized: "Record Screen"), action: #selector(recordScreen))
        recordScreen.setShortcut(for: .recordScreen)
        menu.addItem(recordScreen)

        menu.addItem(.separator())

        // TODO: Re-enable "Capture History..." once the history feature is
        // implemented. The `openHistory()` handler below is currently an
        // empty stub (Phase 2), so showing the menu item just gives users a
        // dead click. Uncomment the two lines below when history lands.
        // menu.addItem(menuItem("Capture History...", action: #selector(openHistory)))
        // menu.addItem(.separator())

        menu.addItem(menuItem(String(localized: "Preferences..."), action: #selector(openPreferences), key: ",", modifiers: [.command]))
        menu.addItem(menuItem(String(localized: "About Capso"), action: #selector(openAbout)))
        menu.addItem(.separator())
        menu.addItem(menuItem(String(localized: "Quit Capso"), action: #selector(quitApp), key: "q", modifiers: [.command]))

        return menu
    }

    private func menuItem(_ title: String, action: Selector?, key: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    @objc private func captureArea() {
        captureCoordinator.captureArea()
    }

    @objc private func captureFullscreen() {
        captureCoordinator.captureFullscreen()
    }

    @objc private func captureWindow() {
        captureCoordinator.captureWindow()
    }

    @objc private func captureText() {
        ocrCoordinator.startInstantOCR()
    }

    @objc private func recordScreen() {
        recordingCoordinator.startRecordingFlow()
    }

    // TODO: Implement Capture History (Phase 2). Keep this stub so the
    // commented-out menu item in `buildMenu()` can be wired back in with a
    // single-line uncomment once the feature is ready.
    @objc private func openHistory() {}

    @objc private func openPreferences() {
        onShowPreferences()
    }

    @objc private func openAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Update shortcut display when menu opens

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Refresh shortcut display from KeyboardShortcuts in case user changed them
        for item in menu.items {
            switch item.action {
            case #selector(captureArea): item.setShortcut(for: .captureArea)
            case #selector(captureFullscreen): item.setShortcut(for: .captureFullscreen)
            case #selector(captureWindow): item.setShortcut(for: .captureWindow)
            case #selector(captureText): item.setShortcut(for: .captureText)
            case #selector(recordScreen): item.setShortcut(for: .recordScreen)
            default: break
            }
        }
    }
}
