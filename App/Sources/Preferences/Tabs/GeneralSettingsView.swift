// App/Sources/Preferences/Tabs/GeneralSettingsView.swift
import SwiftUI
import LaunchAtLogin
import AppKit
import KeyboardShortcuts
import SharedKit

struct GeneralSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel
    let updateManager: UpdateManager?
    @State private var showHideMenuBarConfirmation = false

    private var menuBarToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showMenuBarIcon },
            set: { newValue in
                if newValue {
                    viewModel.showMenuBarIcon = true
                } else {
                    showHideMenuBarConfirmation = true
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General")
                .font(.system(size: 20, weight: .bold))

            SettingGroup(title: "Startup") {
                SettingCard {
                    SettingRow(label: "Launch at Login", sublabel: "Start Capso when you log in") {
                        LaunchAtLogin.Toggle { Text("") }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Show Menu Bar Icon", sublabel: "Hide for a minimalist menu bar — shortcuts still work", showDivider: true) {
                        Toggle("", isOn: menuBarToggleBinding)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            SettingGroup(title: "Automation") {
                SettingCard {
                    SettingRow(
                        label: "Automation URLs",
                        sublabel: "Allow Alfred, Raycast, Shortcuts, and other apps to trigger captures"
                    ) {
                        Toggle("", isOn: $viewModel.automationURLsEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Supported URLs", showDivider: true) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: "capso://grab/area")
                            Text(verbatim: "capso://grab/fullscreen")
                            Text(verbatim: "capso://grab/window")
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    }
                }
            }

            SettingGroup(title: "Sound") {
                SettingCard {
                    SettingRow(label: "Shutter Sound", sublabel: "Play sound after capture") {
                        Toggle("", isOn: $viewModel.playShutterSound)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            if let updateManager {
                SettingGroup(title: "Updates") {
                    SettingCard {
                        SettingRow(label: "Automatically Install Updates", sublabel: "Install updates in the background when available") {
                            Toggle("", isOn: Binding(
                                get: { updateManager.automaticallyDownloadsUpdates },
                                set: { updateManager.automaticallyDownloadsUpdates = $0 }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        SettingRow(label: "Check for Updates", sublabel: "Automatically checks daily", showDivider: true) {
                            CheckForUpdatesView(updateManager: updateManager)
                        }
                    }
                }
            }

            SettingGroup(title: "History") {
                SettingCard {
                    SettingRow(label: "Save to History", sublabel: "Automatically save all captures") {
                        Toggle("", isOn: $viewModel.historyEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Keep History", sublabel: "Auto-delete older captures", showDivider: true) {
                        Picker("", selection: $viewModel.historyRetention) {
                            Text("1 Week").tag("oneWeek")
                            Text("2 Weeks").tag("twoWeeks")
                            Text("1 Month").tag("oneMonth")
                            Text("Unlimited").tag("unlimited")
                        }
                        .frame(width: 130)
                    }
                }
            }

            SettingGroup(title: "Diagnostics") {
                SettingCard {
                    SettingRow(label: "Diagnostic Logging", sublabel: "Write local troubleshooting logs when enabled") {
                        Toggle("", isOn: $viewModel.diagnosticLoggingEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Diagnostic Logs", sublabel: "Open Capso's local log folder", showDivider: true) {
                        ExternalLinkButton(title: "Open", icon: "folder") {
                            openDiagnosticLogs()
                        }
                    }
                    SettingRow(label: "Crash Reports", sublabel: "Open macOS DiagnosticReports", showDivider: true) {
                        ExternalLinkButton(title: "Open", icon: "doc.text.magnifyingglass") {
                            openCrashReports()
                        }
                    }
                }
            }

            SettingGroup(title: "About") {
                SettingCard {
                    SettingRow(label: "Version") {
                        Text(viewModel.appVersion)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .fontDesign(.monospaced)
                    }
                    SettingRow(label: "Report a Bug", sublabel: "Found something broken?", showDivider: true) {
                        ExternalLinkButton(title: "Report", icon: "ladybug") {
                            openURL("https://github.com/lzhgus/Capso/issues/new?template=bug_report.yml&labels=bug")
                        }
                    }
                    SettingRow(label: "Request a Feature", sublabel: "Have an idea?", showDivider: true) {
                        ExternalLinkButton(title: "Request", icon: "lightbulb") {
                            openURL("https://github.com/lzhgus/Capso/issues/new?template=feature_request.yml&labels=enhancement")
                        }
                    }
                    SettingRow(label: "Source Code", sublabel: "View on GitHub", showDivider: true) {
                        ExternalLinkButton(title: "Open", icon: "chevron.left.forwardslash.chevron.right") {
                            openURL("https://github.com/lzhgus/Capso")
                        }
                    }
                    SettingRow(label: "Follow on X", sublabel: "Updates from @lzhgus", showDivider: true) {
                        ExternalLinkButton(title: "Follow", icon: "at") {
                            openURL("https://x.com/lzhgus")
                        }
                    }
                }
            }
        }
        .alert("Hide menu bar icon?", isPresented: $showHideMenuBarConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Hide Icon", role: .destructive) {
                viewModel.showMenuBarIcon = false
            }
        } message: {
            Text(hideMenuBarMessage)
        }
    }

    private var hideMenuBarMessage: String {
        let captureArea = shortcutDescription(for: .captureArea) ?? String(localized: "not set")
        let recordScreen = shortcutDescription(for: .recordScreen) ?? String(localized: "not set")
        let history = shortcutDescription(for: .screenshotHistory) ?? String(localized: "not set")
        return String(
            format: String(localized: "Capso will keep running, and your global shortcuts still work:\n\n• Capture Area: %@\n• Record Screen: %@\n• Screenshot History: %@\n\nTo open Preferences again, launch Capso from Spotlight, Launchpad, or Finder — even while it's still running."),
            captureArea, recordScreen, history
        )
    }

    private func shortcutDescription(for name: KeyboardShortcuts.Name) -> String? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return nil }
        return shortcut.description
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openDiagnosticLogs() {
        let logFileURL = DiagnosticLogger.prepareLogFile()
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }

    private func openCrashReports() {
        let directory = DiagnosticLogger.diagnosticReportDirectories.first!
        NSWorkspace.shared.open(directory)
    }
}

private struct ExternalLinkButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 12))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .preferencesGlassActionBackground(isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { isHovered = $0 }
    }
}
