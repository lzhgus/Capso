import AppKit
import Carbon.HIToolbox
import SwiftUI
@preconcurrency import KeyboardShortcuts

struct ShortcutRecorderControl: NSViewRepresentable {
    let name: KeyboardShortcuts.Name

    func makeNSView(context: Context) -> ShortcutRecorderContainer {
        ShortcutRecorderContainer(name: name)
    }

    func updateNSView(_ view: ShortcutRecorderContainer, context: Context) {
        if view.name != name {
            view.finishRecording()
            view.name = name
        }
        view.refreshTitle()
    }

    static func dismantleNSView(_ view: ShortcutRecorderContainer, coordinator: ()) {
        view.finishRecording()
    }
}

/// Own the recording session instead of treating shortcut input as text editing.
/// KeyboardShortcuts continues to own persistence and global hotkey registration.
@MainActor
final class ShortcutRecorderContainer: NSView {
    private static weak var activeRecorder: ShortcutRecorderContainer?
    var name: KeyboardShortcuts.Name
    let recordButton = ShortcutRecordButton()
    let clearButton = NSButton()
    private(set) var isRecording = false
    private let shortcuts: [ShortcutCatalog.Entry]
    private(set) var conflictAlert: NSAlert?
    private var shortcutsWereEnabled = true
    private var eventMonitor: Any?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init(name: KeyboardShortcuts.Name, shortcuts: [ShortcutCatalog.Entry] = ShortcutCatalog.entries) {
        self.name = name
        self.shortcuts = shortcuts
        super.init(frame: NSRect(x: 0, y: 0, width: 170, height: 32))
        recordButton.bezelStyle = .rounded
        recordButton.font = .systemFont(ofSize: 12, weight: .medium)
        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        recordButton.setAccessibilityLabel(String(localized: "Record shortcut"))
        clearButton.bezelStyle = .rounded
        clearButton.imagePosition = .imageOnly
        clearButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "Clear shortcut"))
        clearButton.target = self
        clearButton.action = #selector(clearShortcut)
        clearButton.toolTip = String(localized: "Clear shortcut")
        addSubview(recordButton)
        addSubview(clearButton)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    override func layout() {
        super.layout()
        recordButton.frame = NSRect(x: 0, y: 0, width: bounds.width - 30, height: bounds.height)
        clearButton.frame = NSRect(x: bounds.width - 26, y: 0, width: 26, height: bounds.height)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        finishRecording()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        guard let window else { return }
        for notification in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: notification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishRecording() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTitle() }
        })
    }

    @objc private func toggleRecording() {
        if isRecording { finishRecording() } else { beginRecording() }
    }

    func beginRecording() {
        guard let window, !isRecording, window.attachedSheet == nil else { return }
        Self.activeRecorder?.finishRecording()
        window.makeKey()
        window.makeFirstResponder(recordButton)
        shortcutsWereEnabled = KeyboardShortcuts.isEnabled
        KeyboardShortcuts.isEnabled = false
        isRecording = true
        Self.activeRecorder = self
        recordButton.contentTintColor = .controlAccentColor
        showHint(String(localized: "Press a shortcut…"))
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func finishRecording() {
        guard isRecording else { return }
        isRecording = false
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        KeyboardShortcuts.isEnabled = shortcutsWereEnabled
        if Self.activeRecorder === self { Self.activeRecorder = nil }
        recordButton.contentTintColor = nil
        refreshTitle()
    }

    func refreshTitle() {
        guard !isRecording else { return }
        let shortcut = KeyboardShortcuts.getShortcut(for: name)
        recordButton.title = shortcut?.description ?? String(localized: "Set shortcut")
        recordButton.setAccessibilityValue(recordButton.title)
        recordButton.toolTip = String(localized: "Click to record; Esc cancels and Delete clears.")
        clearButton.isEnabled = shortcut != nil
    }

    @objc private func clearShortcut() {
        KeyboardShortcuts.setShortcut(nil, for: name)
        finishRecording()
        refreshTitle()
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if event.window !== window || !bounds.contains(convert(event.locationInWindow, from: nil)) {
                finishRecording()
            }
            return event
        }
        guard event.window === window else { return event }
        let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
        if event.type == .flagsChanged {
            let symbols = [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
                .filter { modifiers.contains($0.0) }.map(\.1).joined()
            showHint(symbols.isEmpty ? String(localized: "Press a shortcut…") : symbols + " …")
            return event
        }
        guard event.type == .keyDown else { return event }
        guard !event.isARepeat else { return nil }
        if modifiers.isEmpty {
            switch event.keyCode {
            case 53: finishRecording(); return nil
            case 51, 117: clearShortcut(); return nil
            case 48: finishRecording(); return event
            default: break
            }
        }
        let isFunctionKey = event.specialKey.map {
            (NSEvent.SpecialKey.f1.rawValue...NSEvent.SpecialKey.f20.rawValue).contains($0.rawValue)
        } ?? false
        guard !modifiers.intersection([.command, .control, .option]).isEmpty || isFunctionKey,
              let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
            showHint(String(localized: "Add ⌘, ⌃ or ⌥"))
            return nil
        }
        if let title = conflictingAction(for: shortcut) {
            showConflict(shortcut, action: title)
            return nil
        }
        if let menu = NSApp.mainMenu, let title = Self.conflictingMenuItem(for: event, in: menu) {
            showConflict(shortcut, action: title)
            return nil
        }
        if Self.isSystemShortcut(shortcut) {
            finishRecording()
            guard let window else { return nil }
            let alert = NSAlert()
            alert.messageText = String(localized: "This shortcut is used by macOS")
            alert.informativeText = String(localized: "Choose another shortcut, or use it anyway if you have disabled the system binding.")
            alert.addButton(withTitle: String(localized: "Cancel"))
            alert.addButton(withTitle: String(localized: "Use Anyway"))
            let requestedName = name
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self, response == .alertSecondButtonReturn else { return }
                // Revalidate after the sheet in case another setting changed meanwhile.
                if let title = self.conflictingAction(for: shortcut, excluding: requestedName) {
                    self.showConflict(shortcut, action: title)
                } else {
                    KeyboardShortcuts.setShortcut(shortcut, for: requestedName)
                    self.refreshTitle()
                }
            }
            return nil
        }
        KeyboardShortcuts.setShortcut(shortcut, for: name)
        finishRecording()
        return nil
    }

    func conflictingAction(for shortcut: KeyboardShortcuts.Shortcut, excluding excludedName: KeyboardShortcuts.Name? = nil) -> String? {
        shortcuts.first {
            $0.name != (excludedName ?? name) && KeyboardShortcuts.getShortcut(for: $0.name) == shortcut
        }?.title
    }

    private func showConflict(_ shortcut: KeyboardShortcuts.Shortcut, action: String) {
        finishRecording()
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Shortcut already in use")
        let format = String(localized: "The shortcut %@ is already used by “%@”. Choose another combination, or clear the existing binding first.")
        alert.informativeText = String(format: format, shortcut.description, action)
        alert.addButton(withTitle: String(localized: "OK"))
        conflictAlert = alert
        alert.beginSheetModal(for: window) { [weak self] _ in
            self?.conflictAlert = nil
        }
    }

    private func showHint(_ message: String) {
        recordButton.title = message
        recordButton.setAccessibilityValue(message)
        recordButton.toolTip = message
    }

    static func conflictingMenuItem(for event: NSEvent, in menu: NSMenu) -> String? {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""
        for item in menu.items {
            var itemFlags = item.keyEquivalentModifierMask.intersection([.command, .control, .option, .shift])
            if item.keyEquivalent != item.keyEquivalent.lowercased() { itemFlags.insert(.shift) }
            if !characters.isEmpty, !item.keyEquivalent.isEmpty,
               item.keyEquivalent.lowercased() == characters, itemFlags == flags {
                return item.title
            }
            if let submenu = item.submenu, let title = conflictingMenuItem(for: event, in: submenu) { return title }
        }
        return nil
    }

    private static func isSystemShortcut(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        // Like KeyboardShortcuts' recorder, allow the standard unmodified F12.
        guard shortcut != .init(.f12) else { return false }
        var values: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&values) == noErr,
              let entries = values?.takeRetainedValue() as? [[String: Any]] else { return false }
        return entries.contains {
            ($0[kHISymbolicHotKeyEnabled] as? Bool) == true
                && ($0[kHISymbolicHotKeyCode] as? Int) == shortcut.carbonKeyCode
                && ($0[kHISymbolicHotKeyModifiers] as? Int) == shortcut.carbonModifiers
        }
    }
}

final class ShortcutRecordButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
