// App/Sources/Preferences/Tabs/ScreenshotSettingsView.swift
import SwiftUI
import SharedKit

struct ScreenshotSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel

    @State private var showingAddPreset = false
    @State private var newPresetType = 0  // 0 = aspect ratio, 1 = fixed size
    @State private var newWidth = ""
    @State private var newHeight = ""
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Screenshots")
                .font(.system(size: 20, weight: .bold))

            SettingGroup(title: "After Capture") {
                SettingCard {
                    SettingRow(label: "Show Preview", sublabel: "Display thumbnail with quick actions") {
                        Toggle("", isOn: $viewModel.screenshotShowPreview)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Copy to Clipboard", sublabel: "Copy screenshot immediately", showDivider: true) {
                        Toggle("", isOn: $viewModel.screenshotAutoCopy)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Auto Save", sublabel: "Save to file automatically", showDivider: true) {
                        Toggle("", isOn: $viewModel.screenshotAutoSave)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            SettingGroup(title: "Capture") {
                SettingCard {
                    SettingRow(label: "Show Cursor", sublabel: "Include the mouse pointer in screenshots") {
                        Toggle("", isOn: $viewModel.screenshotShowsCursor)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Capture Window Shadow", sublabel: "Include shadow in window captures", showDivider: true) {
                        Toggle("", isOn: $viewModel.captureWindowShadow)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    // TODO: Re-enable the rows below once underlying
                    // behaviors are implemented (showMagnifier,
                    // rememberLastCaptureArea).
                }
            }

            SettingGroup(title: "Timestamp") {
                SettingCard {
                    SettingRow(label: "Add Timestamp", sublabel: "Draw the capture time onto screenshots") {
                        Toggle("", isOn: $viewModel.screenshotTimestampEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }

                    if viewModel.screenshotTimestampEnabled {
                        SettingRow(label: "Position", showDivider: true) {
                            Picker("", selection: $viewModel.screenshotTimestampPosition) {
                                ForEach(ScreenshotTimestampPosition.allCases, id: \.self) { position in
                                    Text(position.displayName).tag(position)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }

                        SettingRow(label: "Format", showDivider: true) {
                            Picker("", selection: $viewModel.screenshotTimestampFormat) {
                                ForEach(ScreenshotTimestampFormat.allCases, id: \.self) { format in
                                    Text(format.displayName).tag(format)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }

                        SettingRow(label: "Color", showDivider: true) {
                            TextField("#FFFFFF", text: $viewModel.screenshotTimestampColorHex)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 88)
                        }

                        SettingRow(label: "Font Size", showDivider: true) {
                            HStack(spacing: 8) {
                                Text("\(viewModel.screenshotTimestampFontSize) pt")
                                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                                    .frame(minWidth: 42, alignment: .trailing)
                                Stepper(
                                    "",
                                    value: $viewModel.screenshotTimestampFontSize,
                                    in: ScreenshotTimestampOptions.fontSizeRange
                                )
                                .labelsHidden()
                            }
                        }
                    }
                }
            }

            SettingGroup(title: "Self-Timer") {
                SettingCard {
                    SettingRow(
                        label: "Default Duration",
                        sublabel: "Delay before the screenshot fires"
                    ) {
                        HStack(spacing: 8) {
                            Text("\(viewModel.selfTimerDurationSeconds)s")
                                .font(.system(size: 13, weight: .medium).monospacedDigit())
                                .frame(minWidth: 32, alignment: .trailing)
                            Stepper(
                                "",
                                value: $viewModel.selfTimerDurationSeconds,
                                in: AppSettings.selfTimerDurationRange
                            )
                            .labelsHidden()
                        }
                    }
                    SettingRow(
                        label: "Tick Sound",
                        sublabel: "Play a sound on each second of the countdown",
                        showDivider: true
                    ) {
                        Toggle("", isOn: $viewModel.selfTimerPlayTickSound)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }

                Text("Useful for capturing menus, hover states, and other UI that disappears the moment you move the mouse.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            SettingGroup(title: "Capture Presets") {
                SettingCard {
                    SettingRow(
                        label: "Capture Presets",
                        sublabel: "Constrain area capture to preset aspect ratios or fixed sizes"
                    ) {
                        Toggle("", isOn: $viewModel.capturePresetsEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }

                if viewModel.capturePresetsEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Press **R** to cycle presets during area capture", systemImage: "keyboard")
                        Label("**Right-click** to open the preset picker", systemImage: "cursorarrow.click.2")
                        Label("**Shift + R** to cycle in reverse", systemImage: "arrow.left.arrow.right")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)

                    SettingCard {
                    // Built-in aspect ratios (skip .freeform)
                    let aspectRatios = CapturePreset.builtinAspectRatios.filter {
                        if case .freeform = $0 { return false }
                        return true
                    }
                    ForEach(Array(aspectRatios.enumerated()), id: \.element.id) { index, preset in
                        let isHidden = viewModel.hiddenBuiltinPresets.contains(preset)
                        SettingRow(
                            label: LocalizedStringKey(preset.displayName),
                            showDivider: index > 0
                        ) {
                            Toggle("", isOn: Binding(
                                get: { !isHidden },
                                set: { isOn in
                                    if isOn {
                                        viewModel.hiddenBuiltinPresets.remove(preset)
                                    } else {
                                        viewModel.hiddenBuiltinPresets.insert(preset)
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                    }

                    // Built-in fixed sizes
                    ForEach(Array(CapturePreset.builtinFixedSizes.enumerated()), id: \.element.id) { index, preset in
                        let isHidden = viewModel.hiddenBuiltinPresets.contains(preset)
                        SettingRow(
                            label: LocalizedStringKey(preset.displayName),
                            showDivider: true
                        ) {
                            Toggle("", isOn: Binding(
                                get: { !isHidden },
                                set: { isOn in
                                    if isOn {
                                        viewModel.hiddenBuiltinPresets.remove(preset)
                                    } else {
                                        viewModel.hiddenBuiltinPresets.insert(preset)
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                    }

                    // Custom presets
                    ForEach(viewModel.customCapturePresets) { preset in
                        SettingRow(
                            label: LocalizedStringKey(preset.displayName),
                            showDivider: true
                        ) {
                            Button {
                                viewModel.customCapturePresets.removeAll { $0.id == preset.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                    Button("Add Custom Preset") {
                        showingAddPreset = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                    .padding(.leading, 2)
                } // if capturePresetsEnabled
            }

        }
        .sheet(isPresented: $showingAddPreset) {
            addPresetSheet
        }
    }

    // MARK: - Add Preset Sheet

    @ViewBuilder
    private var addPresetSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Custom Preset")
                .font(.system(size: 17, weight: .semibold))

            Picker("", selection: $newPresetType) {
                Text("Aspect Ratio").tag(0)
                Text("Fixed Size").tag(1)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(newPresetType == 0 ? LocalizedStringKey("Width ratio") : LocalizedStringKey("Width (px)"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        TextField("e.g. 16", text: $newWidth)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(newPresetType == 0 ? LocalizedStringKey("Height ratio") : LocalizedStringKey("Height (px)"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        TextField("e.g. 9", text: $newHeight)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey("Name (optional)"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Widescreen", text: $newName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button("Cancel") {
                    showingAddPreset = false
                    resetNewPresetFields()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    addCustomPreset()
                    showingAddPreset = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(Int(newWidth) == nil || Int(newHeight) == nil)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    // MARK: - Helpers

    private func addCustomPreset() {
        guard let w = Int(newWidth), let h = Int(newHeight) else { return }
        let name: String? = newName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newName.trimmingCharacters(in: .whitespaces)
        let preset: CapturePreset = newPresetType == 0
            ? .aspectRatio(width: w, height: h, name: name)
            : .fixedSize(width: w, height: h, name: name)
        viewModel.customCapturePresets.append(preset)
        resetNewPresetFields()
    }

    private func resetNewPresetFields() {
        newPresetType = 0
        newWidth = ""
        newHeight = ""
        newName = ""
    }
}
