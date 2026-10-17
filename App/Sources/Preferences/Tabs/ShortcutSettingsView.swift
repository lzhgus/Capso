// App/Sources/Preferences/Tabs/ShortcutSettingsView.swift
import SwiftUI
import AppKit
import KeyboardShortcuts
import SharedKit

extension KeyboardShortcuts.Name {
    static let captureAllInOne = Self("captureAllInOne")
    static let captureArea = Self("captureArea", default: .init(.one, modifiers: [.option, .shift]))
    static let captureFullscreen = Self("captureFullscreen", default: .init(.two, modifiers: [.option, .shift]))
    static let captureWindow = Self("captureWindow", default: .init(.three, modifiers: [.option, .shift]))
    static let captureText = Self("captureText", default: .init(.four, modifiers: [.option, .shift]))
    /// Keep the existing storage key so current users retain their recording shortcut.
    static let recordScreen = Self("recordScreen", default: .init(.five, modifiers: [.option, .shift]))
    /// Opt-in to avoid adding another default global shortcut.
    static let recordFullscreen = Self("recordFullscreen")
    static let captureScrolling = Self("captureScrolling", default: .init(.six, modifiers: [.option, .shift]))
    static let captureAreaToClipboard = Self("captureAreaToClipboard", default: .init(.seven, modifiers: [.option, .shift]))
    static let captureAreaAndShare = Self("captureAreaAndShare", default: .init(.zero, modifiers: [.option, .shift]))
    static let captureAreaAndAnnotate = Self("captureAreaAndAnnotate", default: .init(.eight, modifiers: [.option, .shift]))
    static let captureAreaAndPin = Self("captureAreaAndPin")
    static let pinFromClipboard = Self("pinFromClipboard")
    static let editClipboardImage = Self("editClipboardImage")
    static let screenshotHistory = Self("screenshotHistory", default: .init(.nine, modifiers: [.option, .shift]))
    static let captureAndTranslate = Self("captureAndTranslate", default: .init(.t, modifiers: [.option, .shift]))
    static let translateSelectedText = Self("translateSelectedText", default: .init(.y, modifiers: [.option, .shift]))
    static let translateTypedText = Self("translateTypedText")
    /// No default binding — opt-in. Self-Timer is discoverable from the
    /// menu bar; shipping a default risks colliding with whatever the user
    /// has already bound in macOS or third-party apps.
    static let selfTimerCapture = Self("selfTimerCapture")
    /// Replays the last capture (area / window / fullscreen) without showing
    /// the selection overlay. Unbound by default — user must assign a key.
    static let captureLastArea = Self("captureLastArea")
    /// Unbound by default.
    static let togglePins = Self("togglePins")

    static let allCapso: [Self] = [
        .captureAllInOne, .captureArea, .captureFullscreen, .captureWindow, .captureText, .recordScreen,
        .recordFullscreen, .captureScrolling, .captureAreaToClipboard, .captureAreaAndShare,
        .captureAreaAndAnnotate, .captureAreaAndPin, .pinFromClipboard, .editClipboardImage, .screenshotHistory,
        .captureAndTranslate, .translateSelectedText, .translateTypedText, .selfTimerCapture, .captureLastArea, .togglePins,
    ]
}

/// The settings list and duplicate detection share the same global shortcut catalog.
/// Panel-specific shortcuts are intentionally outside this catalog.
enum ShortcutCatalog {
    struct Entry {
        let name: KeyboardShortcuts.Name
        let title: String
        var help: LocalizedStringKey? = nil
    }

    static var entries: [Entry] {
        [
            .init(name: .captureAllInOne, title: String(localized: "All-in-One")),
            .init(name: .captureArea, title: String(localized: "Capture Area")),
            .init(name: .captureFullscreen, title: String(localized: "Capture Fullscreen")),
            .init(name: .captureWindow, title: String(localized: "Capture Window")),
            .init(name: .captureText, title: String(localized: "Capture Text (OCR)")),
            .init(name: .captureScrolling, title: String(localized: "Scrolling Capture")),
            .init(name: .selfTimerCapture, title: String(localized: "Self-Timer")),
            .init(name: .captureAreaToClipboard, title: String(localized: "Capture Area to Clipboard")),
            .init(name: .captureAreaAndShare, title: String(localized: "Capture and Share to Cloud")),
            .init(name: .captureAreaAndAnnotate, title: String(localized: "Capture Area & Annotate")),
            .init(name: .captureAreaAndPin, title: String(localized: "Capture Area & Pin")),
            .init(name: .pinFromClipboard, title: String(localized: "Pin from Clipboard"), help: "Float copied images, text, colors, or files above other windows"),
            .init(name: .editClipboardImage, title: String(localized: "Edit Clipboard Image"), help: "Open the image currently copied to the clipboard in Annotate"),
            .init(name: .togglePins, title: String(localized: "Hide / Show All Pins")),
            .init(name: .captureAndTranslate, title: String(localized: "Capture & Translate")),
            .init(name: .translateSelectedText, title: String(localized: "Translate Selected Text")),
            .init(name: .translateTypedText, title: String(localized: "Translate Typed Text")),
            .init(name: .captureLastArea, title: String(localized: "Capture Previous Area")),
            .init(name: .recordScreen, title: String(localized: "Record Area")),
            .init(name: .recordFullscreen, title: String(localized: "Record Full Screen")),
            .init(name: .screenshotHistory, title: String(localized: "Screenshot History"))
        ]
    }
}

struct ShortcutSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel
    private struct ContextualShortcut: Identifiable {
        let id: String
        let scope: LocalizedStringKey
        let action: LocalizedStringKey
        /// One or more keycaps to render for this action. `.copy` in
        /// All-in-One lists all three bindings (⌘C, Return, ⌘⇧C) so users
        /// discover Return and ⌘⇧C alongside ⌘C — see issue #237.
        let shortcuts: [String]
    }

    private let contextualShortcuts: [ContextualShortcut] = [
        ContextualShortcut(id: "all-in-one-copy", scope: "All-in-One", action: "Copy selected area", shortcuts: ["⌘C", "⏎", "⌘⇧C"]),
        ContextualShortcut(id: "all-in-one-save", scope: "All-in-One", action: "Save selected area", shortcuts: ["⌘S"]),
        ContextualShortcut(id: "all-in-one-pin", scope: "All-in-One", action: "Pin selected area", shortcuts: ["⌘P"]),
        ContextualShortcut(id: "all-in-one-cancel", scope: "All-in-One", action: "Cancel", shortcuts: ["Esc"]),
        ContextualShortcut(id: "window-multi-select", scope: "Window Capture", action: "Select multiple windows", shortcuts: ["⇧ + click"]),
        ContextualShortcut(id: "window-multi-confirm", scope: "Window Capture", action: "Capture selected windows", shortcuts: ["Release ⇧"]),
        ContextualShortcut(id: "quick-access-copy", scope: "Quick Access", action: "Copy", shortcuts: ["⌘C"]),
        ContextualShortcut(id: "quick-access-save", scope: "Quick Access", action: "Save", shortcuts: ["⌘S"]),
        ContextualShortcut(id: "quick-access-annotate", scope: "Quick Access", action: "Annotate", shortcuts: ["⌘E"]),
        ContextualShortcut(id: "quick-access-pin", scope: "Quick Access", action: "Pin", shortcuts: ["⌘P"])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Shortcuts")
                .font(.system(size: 20, weight: .bold))

            // Info banner
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("Click a customizable shortcut to record a new combination. Press Esc to cancel or Delete to remove. Contextual shortcuts are fixed and work only while that panel is active.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 0.5)
            )

            SystemScreenshotShortcutsCard()

            SettingGroup(title: "Customizable Shortcuts") {
                SettingCard {
                    ForEach(Array(ShortcutCatalog.entries.enumerated()), id: \.element.name) { index, entry in
                        shortcutRow(
                            LocalizedStringKey(entry.title), name: entry.name,
                            showDivider: index > 0, help: entry.help
                        )
                    }
                }
            }

            SettingGroup(title: "Contextual Shortcuts") {
                SettingCard {
                    centerLockRow
                    ForEach(Array(contextualShortcuts.enumerated()), id: \.element.id) { _, item in
                        contextualShortcutRow(item, showDivider: true)
                    }
                }
            }
        }
    }

    private var centerLockRow: some View {
        SettingRow(
            label: "Center 1:1 from click",
            sublabel: "Selection",
            showDivider: false
        ) {
            HStack(spacing: 6) {
                ShortcutKeycap(text: "⇧")
                Text("+")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                SquareCenterLockKeyRecorder(shortcut: $viewModel.squareCenterLockShortcut)
            }
        }
        .help("Hold Shift for 1:1, then this extra key to grow from the click as the center. Shift cannot be changed.")
    }

    @ViewBuilder
    private func shortcutRow(
        _ label: LocalizedStringKey,
        name: KeyboardShortcuts.Name,
        showDivider: Bool = false,
        help: LocalizedStringKey? = nil
    ) -> some View {
        let row = SettingRow(label: label, showDivider: showDivider) {
            ShortcutRecorderControl(name: name)
                .frame(width: 170, height: 32)
        }

        if let help {
            row.help(help)
        } else {
            row
        }
    }

    private func contextualShortcutRow(_ item: ContextualShortcut, showDivider: Bool = false) -> some View {
        SettingRow(label: item.action, sublabel: item.scope, showDivider: showDivider) {
            HStack(spacing: 6) {
                ForEach(Array(item.shortcuts.enumerated()), id: \.offset) { _, shortcut in
                    ShortcutKeycap(text: shortcut)
                }
            }
        }
    }
}

private struct SquareCenterLockKeyRecorder: View {
    @Binding var shortcut: SquareCenterLockShortcut
    @State private var isRecording = false

    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            Text(isRecording ? "…" : shortcut.displayCharacter)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    Color.primary.opacity(isRecording ? 0.12 : 0.08),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isRecording ? Color.accentColor : Color.primary.opacity(0.10),
                            lineWidth: isRecording ? 1.5 : 0.5
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Extra key for centered 1:1")
        .accessibilityValue(shortcut.displayCharacter)
        .help("Click to record a different extra key")
        .background {
            if isRecording {
                CenterLockKeyCapture { event in
                    if event.keyCode == 53 {
                        isRecording = false
                        return
                    }
                    if let recorded = SquareCenterLockShortcut(event: event) {
                        shortcut = recorded
                        isRecording = false
                    }
                }
            }
        }
    }
}

/// Local key-down monitor used only while the extra-key recorder is listening.
private struct CenterLockKeyCapture: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        var onKeyDown: (NSEvent) -> Void
        private var monitor: Any?

        init(onKeyDown: @escaping (NSEvent) -> Void) {
            self.onKeyDown = onKeyDown
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.onKeyDown(event)
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private struct ShortcutKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
    }
}

/// Helps hand ⇧⌘3 / ⇧⌘4 / ⇧⌘5 over from the macOS screenshot tool to Capso.
private struct SystemScreenshotShortcutsCard: View {
    @State private var systemShortcutsOn = SystemScreenshotShortcuts.areEnabled
    @State private var capsoUsesAny = Self.capsoUsesAnySystemKey

    private static let assignments: [(KeyboardShortcuts.Name, KeyboardShortcuts.Key)] = [
        (.captureFullscreen, .three), (.captureArea, .four), (.captureAllInOne, .five),
    ]

    /// Once any Capso action uses one of these keys, the user has set them up themselves.
    private static var capsoUsesAnySystemKey: Bool {
        let systemKeys = assignments.map { KeyboardShortcuts.Shortcut($0.1, modifiers: [.command, .shift]) }
        return KeyboardShortcuts.Name.allCapso.contains { name in
            KeyboardShortcuts.getShortcut(for: name).map(systemKeys.contains) ?? false
        }
    }

    var body: some View {
        Group {
            if systemShortcutsOn {
                banner(
                    icon: "exclamationmark.triangle",
                    tint: .orange,
                    text: "macOS still uses ⇧⌘3, ⇧⌘4 and ⇧⌘5 for its own screenshots. To use them for Capso, turn off the shortcuts under Keyboard Shortcuts → Screenshots."
                ) {
                    Button("Open Keyboard Settings") { NSWorkspace.shared.open(SystemScreenshotShortcuts.settingsURL) }
                }
            } else if !capsoUsesAny {
                banner(
                    icon: "keyboard",
                    tint: .blue,
                    text: "The macOS screenshot shortcuts are off. Capso can take them over: ⇧⌘3 Capture Fullscreen, ⇧⌘4 Capture Area, ⇧⌘5 All-in-One."
                ) {
                    Button("Use ⇧⌘3 / ⇧⌘4 / ⇧⌘5") {
                        for (name, key) in Self.assignments {
                            KeyboardShortcuts.setShortcut(.init(key, modifiers: [.command, .shift]), for: name)
                        }
                        capsoUsesAny = true
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            systemShortcutsOn = SystemScreenshotShortcuts.areEnabled
            capsoUsesAny = Self.capsoUsesAnySystemKey
        }
    }

    private func banner(icon: String, tint: Color, text: LocalizedStringKey, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.2), lineWidth: 0.5))
    }
}
