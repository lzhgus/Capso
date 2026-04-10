// App/Sources/Preferences/Tabs/ExportSettingsView.swift
import SwiftUI
import SharedKit

struct ExportSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel

    private var displayedPath: String {
        viewModel.exportLocation.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Export")
                .font(.system(size: 20, weight: .bold))

            SettingGroup(title: "Quality") {
                SettingCard {
                    SettingRow(label: "Export Quality", sublabel: "Applies to video and GIF exports") {
                        Picker("", selection: $viewModel.exportQuality) {
                            Text("Maximum").tag(ExportQuality.maximum)
                            Text("Social").tag(ExportQuality.social)
                            Text("Web").tag(ExportQuality.web)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                }
            }

            SettingGroup(title: "Save Location") {
                SettingCard {
                    SettingRow(label: "Export To") {
                        HStack(spacing: 8) {
                            Text(displayedPath)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 200, alignment: .trailing)
                            Button("Choose…") {
                                chooseExportLocation()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func chooseExportLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Select")
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.setExportLocation(url)
        }
    }
}
