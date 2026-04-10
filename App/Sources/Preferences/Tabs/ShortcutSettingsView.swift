// App/Sources/Preferences/Tabs/ShortcutSettingsView.swift
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureArea = Self("captureArea", default: .init(.one, modifiers: [.option, .shift]))
    static let captureFullscreen = Self("captureFullscreen", default: .init(.two, modifiers: [.option, .shift]))
    static let captureWindow = Self("captureWindow", default: .init(.three, modifiers: [.option, .shift]))
    static let captureText = Self("captureText", default: .init(.four, modifiers: [.option, .shift]))
    static let recordScreen = Self("recordScreen", default: .init(.five, modifiers: [.option, .shift]))
}

struct ShortcutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Shortcuts")
                .font(.system(size: 20, weight: .bold))

            // Info banner
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("Click a shortcut to record a new combination. Press **Esc** to cancel or **Delete** to remove.")
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

            SettingGroup(title: "Capture") {
                SettingCard {
                    shortcutRow("Capture Area", name: .captureArea)
                    shortcutRow("Capture Fullscreen", name: .captureFullscreen, showDivider: true)
                    shortcutRow("Capture Window", name: .captureWindow, showDivider: true)
                    shortcutRow("Capture Text (OCR)", name: .captureText, showDivider: true)
                }
            }

            SettingGroup(title: "Recording") {
                SettingCard {
                    shortcutRow("Start / Stop Recording", name: .recordScreen)
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


}
