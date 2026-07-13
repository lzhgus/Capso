// App/Sources/Preferences/Tabs/QuickAccessSettingsView.swift
import SwiftUI
import SharedKit

struct QuickAccessSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Quick Access")
                .font(.system(size: 20, weight: .bold))

            SettingGroup(title: "Position") {
                SettingCard {
                    SettingRow(label: "Preview Position", sublabel: "Where the floating preview appears") {
                        Picker("", selection: $viewModel.quickAccessPosition) {
                            Text("↙ Bottom Left").tag(QuickAccessPosition.bottomLeft)
                            Text("◎ Center").tag(QuickAccessPosition.centerScreen)
                            Text("↘ Bottom Right").tag(QuickAccessPosition.bottomRight)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 300)
                    }
                }
            }

            SettingGroup(title: "Auto-Close") {
                SettingCard {
                    SettingRow(label: "Auto-Close Preview", sublabel: "Dismiss after timeout") {
                        Toggle("", isOn: $viewModel.quickAccessAutoClose)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Close After", showDivider: true) {
                        Picker("", selection: $viewModel.quickAccessAutoCloseInterval) {
                            Text("5s").tag(5)
                            Text("10s").tag(10)
                            Text("15s").tag(15)
                            Text("30s").tag(30)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        .disabled(!viewModel.quickAccessAutoClose)
                    }
                }
            }
        }
    }


}
