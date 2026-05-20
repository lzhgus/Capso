// App/Sources/Preferences/Tabs/ShortcutSettingsView.swift
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureAllInOne = Self("captureAllInOne")
    static let captureArea = Self("captureArea", default: .init(.one, modifiers: [.option, .shift]))
    static let captureFullscreen = Self("captureFullscreen", default: .init(.two, modifiers: [.option, .shift]))
    static let captureWindow = Self("captureWindow", default: .init(.three, modifiers: [.option, .shift]))
    static let captureText = Self("captureText", default: .init(.four, modifiers: [.option, .shift]))
    static let recordScreen = Self("recordScreen", default: .init(.five, modifiers: [.option, .shift]))
    static let captureScrolling = Self("captureScrolling", default: .init(.six, modifiers: [.option, .shift]))
    static let captureAreaToClipboard = Self("captureAreaToClipboard", default: .init(.seven, modifiers: [.option, .shift]))
    static let captureAreaAndShare = Self("captureAreaAndShare", default: .init(.zero, modifiers: [.option, .shift]))
    static let captureAreaAndAnnotate = Self("captureAreaAndAnnotate", default: .init(.eight, modifiers: [.option, .shift]))
    static let screenshotHistory = Self("screenshotHistory", default: .init(.nine, modifiers: [.option, .shift]))
    static let captureAndTranslate = Self("captureAndTranslate", default: .init(.t, modifiers: [.command, .shift]))
    /// No default binding — opt-in. Self-Timer is discoverable from the
    /// menu bar; shipping a default risks colliding with whatever the user
    /// has already bound in macOS or third-party apps.
    static let selfTimerCapture = Self("selfTimerCapture")
    /// Replays the last capture (area / window / fullscreen) without showing
    /// the selection overlay. Unbound by default — user must assign a key.
    static let captureLastArea = Self("captureLastArea")
}

struct ShortcutSettingsView: View {
    private struct ContextualShortcut: Identifiable {
        let id: String
        let scope: LocalizedStringKey
        let action: LocalizedStringKey
        let shortcut: String
    }

    private let contextualShortcuts: [ContextualShortcut] = [
        ContextualShortcut(id: "all-in-one-copy", scope: "All-in-One", action: "Copy selected area", shortcut: "⌘C"),
        ContextualShortcut(id: "all-in-one-save", scope: "All-in-One", action: "Save selected area", shortcut: "⌘S"),
        ContextualShortcut(id: "all-in-one-pin", scope: "All-in-One", action: "Pin selected area", shortcut: "⌘P"),
        ContextualShortcut(id: "all-in-one-cancel", scope: "All-in-One", action: "Cancel", shortcut: "Esc"),
        ContextualShortcut(id: "quick-access-copy", scope: "Quick Access", action: "Copy", shortcut: "⌘C"),
        ContextualShortcut(id: "quick-access-save", scope: "Quick Access", action: "Save", shortcut: "⌘S"),
        ContextualShortcut(id: "quick-access-annotate", scope: "Quick Access", action: "Annotate", shortcut: "⌘E"),
        ContextualShortcut(id: "quick-access-pin", scope: "Quick Access", action: "Pin", shortcut: "⌘P")
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

            SettingGroup(title: "Customizable Shortcuts") {
                SettingCard {
                    shortcutRow("All-in-One", name: .captureAllInOne)
                    shortcutRow("Capture Area", name: .captureArea, showDivider: true)
                    shortcutRow("Capture Fullscreen", name: .captureFullscreen, showDivider: true)
                    shortcutRow("Capture Window", name: .captureWindow, showDivider: true)
                    shortcutRow("Capture Text (OCR)", name: .captureText, showDivider: true)
                    shortcutRow("Scrolling Capture", name: .captureScrolling, showDivider: true)
                    shortcutRow("Self-Timer", name: .selfTimerCapture, showDivider: true)
                    shortcutRow("Capture Area to Clipboard", name: .captureAreaToClipboard, showDivider: true)
                    shortcutRow("Capture and Share to Cloud", name: .captureAreaAndShare, showDivider: true)
                    shortcutRow("Capture Area & Annotate", name: .captureAreaAndAnnotate, showDivider: true)
                    shortcutRow("Capture & Translate", name: .captureAndTranslate, showDivider: true)
                    shortcutRow("Capture Previous Area", name: .captureLastArea, showDivider: true)
                    shortcutRow("Start / Stop Recording", name: .recordScreen, showDivider: true)
                    shortcutRow("Screenshot History", name: .screenshotHistory)
                }
            }

            SettingGroup(title: "Contextual Shortcuts") {
                SettingCard {
                    ForEach(Array(contextualShortcuts.enumerated()), id: \.element.id) { index, item in
                        contextualShortcutRow(item, showDivider: index > 0)
                    }
                }
            }
        }
    }

    private func shortcutRow(_ label: LocalizedStringKey, name: KeyboardShortcuts.Name, showDivider: Bool = false) -> some View {
        SettingRow(label: label, showDivider: showDivider) {
            KeyboardShortcuts.Recorder(for: name)
                .controlSize(.small)
        }
    }

    private func contextualShortcutRow(_ item: ContextualShortcut, showDivider: Bool = false) -> some View {
        SettingRow(label: item.action, sublabel: item.scope, showDivider: showDivider) {
            ShortcutKeycap(text: item.shortcut)
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
