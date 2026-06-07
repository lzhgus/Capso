// App/Sources/Preferences/Tabs/ExportSettingsView.swift
import SwiftUI
import SharedKit

struct ExportSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel
    @State private var showingFilenameTokens = false
    @State private var filenameTemplateDraft = ""

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
                    SettingRow(label: "Screenshot Quality", sublabel: "Applies to screenshot files", showDivider: true) {
                        Picker("", selection: $viewModel.screenshotOutputPreset) {
                            Text("PNG").tag(ScreenshotOutputPreset.losslessPNG)
                            Text("JPEG 85%").tag(ScreenshotOutputPreset.standardJPEG)
                            Text("JPEG 70%").tag(ScreenshotOutputPreset.compactJPEG)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
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
                    SettingRow(label: "Monthly Screenshot Folders", sublabel: "Save screenshots into yyyy-MM subfolders", showDivider: true) {
                        Toggle("", isOn: $viewModel.screenshotMonthlyFolders)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    filenameTemplateEditor
                }
            }
        }
        .onAppear {
            filenameTemplateDraft = viewModel.screenshotFilenameTemplate
        }
        .onDisappear {
            normalizeFilenameTemplate()
        }
        .onChange(of: filenameTemplateDraft) { _, newValue in
            viewModel.screenshotFilenameTemplate = newValue
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

    private var filenameTemplateEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.06))
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screenshot Filename")
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                        Text("Extension is added automatically")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        showingFilenameTokens.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .help("Show available filename tokens")
                    .popover(isPresented: $showingFilenameTokens, arrowEdge: .bottom) {
                        filenameTokensPopover
                    }
                    Button {
                        viewModel.resetScreenshotFilenameTemplate()
                        filenameTemplateDraft = viewModel.screenshotFilenameTemplate
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .help("Reset to the default filename template")
                }
                TextField("", text: $filenameTemplateDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit {
                        normalizeFilenameTemplate()
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
                .background(Color.white.opacity(0.06))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Preview")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(viewModel.screenshotFilenamePreview)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func normalizeFilenameTemplate() {
        if filenameTemplateDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.resetScreenshotFilenameTemplate()
            filenameTemplateDraft = viewModel.screenshotFilenameTemplate
        }
    }

    private var filenameTokensPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Filename Tokens")
                .font(.system(size: 13, weight: .semibold))
            tokenRow("{date}", "2026-06-07")
            tokenRow("{time}", "16.11.23")
            tokenRow("{timestamp}", "2026-06-07 at 16.11.23")
            tokenRow("{source}", " - Safari")
            tokenRow("{app}", "Safari")
            tokenRow("{window}", "Example Window")
            tokenRow("{random}", "8-character random text")
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
    }

    private func tokenRow(_ token: String, _ description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(token)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 88, alignment: .leading)
            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
