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
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Preview Position")
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                            Text("Where the floating preview appears")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        Picker("", selection: $viewModel.quickAccessPosition) {
                            Text("↙ Bottom Left").tag(QuickAccessPosition.bottomLeft)
                            Text("◎ Center").tag(QuickAccessPosition.centerScreen)
                            Text("↘ Bottom Right").tag(QuickAccessPosition.bottomRight)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
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
