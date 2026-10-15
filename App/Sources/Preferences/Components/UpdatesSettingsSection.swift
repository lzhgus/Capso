// App/Sources/Preferences/Components/UpdatesSettingsSection.swift
import SwiftUI
import SharedKit

/// The Updates group in Preferences → General.
///
/// Lives in its own view so it can observe `UpdateManager` directly: the
/// frequency and auto-install rows have to grey out as soon as automatic
/// checks are switched off. Greying them leaves both stored values alone, so
/// switching checks back on restores what the user had.
struct UpdatesSettingsSection: View {
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        SettingGroup(title: "Updates") {
            SettingCard {
                SettingRow(
                    label: "Automatically Check for Updates",
                    sublabel: "Look for new versions in the background"
                ) {
                    Toggle("", isOn: $updateManager.automaticallyChecksForUpdates)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .searchHighlightTarget("general-check-updates")
                SettingRow(label: "Check Frequency", showDivider: true) {
                    Picker("", selection: $updateManager.updateCheckFrequency) {
                        Text("Daily").tag(UpdateCheckFrequency.daily)
                        Text("Weekly").tag(UpdateCheckFrequency.weekly)
                        Text("Monthly").tag(UpdateCheckFrequency.monthly)
                    }
                    .frame(width: 130)
                    .disabled(!updateManager.automaticallyChecksForUpdates)
                }
                .searchHighlightTarget("general-check-frequency")
                SettingRow(
                    label: "Automatically Install Updates",
                    sublabel: "Install updates in the background when available",
                    showDivider: true
                ) {
                    Toggle("", isOn: $updateManager.automaticallyDownloadsUpdates)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!updateManager.automaticallyChecksForUpdates)
                }
                .searchHighlightTarget("general-auto-install-updates")
                SettingRow(label: "Check for Updates", sublabel: "Look for a new version now", showDivider: true) {
                    CheckForUpdatesView(updateManager: updateManager)
                }
                .searchHighlightTarget("general-check-now")
            }
        }
    }
}
