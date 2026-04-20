// App/Sources/Preferences/Tabs/RecordingSettingsView.swift
import SwiftUI
import SharedKit

struct RecordingSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Recording")
                .font(.system(size: 20, weight: .bold))

            SettingGroup(title: "Cursor") {
                SettingCard {
                    SettingRow(label: "Show Cursor") {
                        Toggle("", isOn: $viewModel.showCursor)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Highlight Clicks", sublabel: "Radial pulse on mouse click", showDivider: true) {
                        Toggle("", isOn: $viewModel.highlightClicks)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    // TODO: Re-enable "Cursor Smoothing" once Bézier interpolation
                    // of the cursor path is actually implemented in the recording
                    // pipeline. AppSettings.cursorSmoothing is stored but never
                    // read anywhere today.
                    // SettingRow(label: "Cursor Smoothing", sublabel: "Bézier interpolation to reduce jitter", showDivider: true) {
                    //     Toggle("", isOn: $viewModel.cursorSmoothing)
                    //         .toggleStyle(.switch)
                    //         .controlSize(.small)
                    // }
                }
            }

            SettingGroup(title: "Behavior") {
                SettingCard {
                    SettingRow(label: "Show Countdown", sublabel: "3-second countdown before recording") {
                        Toggle("", isOn: $viewModel.showCountdown)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Open Editor After Recording", sublabel: "Edit, trim, and add effects before exporting", showDivider: true) {
                        Toggle("", isOn: $viewModel.openEditorAfterRecording)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    // TODO: Re-enable the two rows below once their behaviors
                    // are implemented. They are stored in AppSettings but
                    // never consumed by RecordingCoordinator:
                    //   - dimScreenWhileRecording: dim non-captured displays
                    //   - rememberLastRecordingArea: persist last recording rect
                    // SettingRow(label: "Dim Screen While Recording", showDivider: true) {
                    //     Toggle("", isOn: $viewModel.dimScreenWhileRecording)
                    //         .toggleStyle(.switch)
                    //         .controlSize(.small)
                    // }
                    // SettingRow(label: "Remember Last Recording Area", showDivider: true) {
                    //     Toggle("", isOn: $viewModel.rememberLastRecordingArea)
                    //         .toggleStyle(.switch)
                    //         .controlSize(.small)
                    // }
                }
            }

            // TODO: Re-enable the "Format" group once AppSettings.recordingFormat
            // is actually honored as the *default* pick in RecordingToolbar.
            // Today the format (MP4 / GIF) is chosen per-session via the
            // toolbar button and the setting value is never read anywhere,
            // so this picker is dead UI.
            // SettingGroup(title: "Format") {
            //     SettingCard {
            //         SettingRow(label: "Default Recording Format") {
            //             Picker("", selection: $viewModel.recordingFormat) {
            //                 Text("MP4").tag(RecordingFormat.mp4)
            //                 Text("GIF").tag(RecordingFormat.gif)
            //             }
            //             .pickerStyle(.segmented)
            //             .frame(width: 140)
            //         }
            //     }
            // }
        }
    }


}
