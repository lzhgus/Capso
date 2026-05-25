import SwiftUI
import SharedKit

struct PermissionSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Permissions")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button(action: refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            SettingGroup(title: "Privacy & Security") {
                SettingCard {
                    permissionRow(
                        kind: .screenRecording,
                        title: "Screen Recording",
                        subtitle: "Required for screenshots and recording",
                        isGranted: viewModel.screenRecordingGranted
                    )
                    permissionRow(
                        kind: .accessibility,
                        title: "Accessibility",
                        subtitle: "Required for selected text translation",
                        isGranted: viewModel.accessibilityGranted,
                        showDivider: true
                    )
                    permissionRow(
                        kind: .camera,
                        title: "Camera",
                        subtitle: "Required for camera overlay",
                        isGranted: viewModel.cameraGranted,
                        showDivider: true
                    )
                    permissionRow(
                        kind: .microphone,
                        title: "Microphone",
                        subtitle: "Required for microphone recording",
                        isGranted: viewModel.microphoneGranted,
                        showDivider: true
                    )
                }
            }
        }
        .task {
            await viewModel.refreshPermissions()
        }
    }

    private func permissionRow(
        kind: PermissionKind,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        isGranted: Bool,
        showDivider: Bool = false
    ) -> some View {
        SettingRow(label: title, sublabel: subtitle, showDivider: showDivider) {
            HStack(spacing: 10) {
                statusBadge(isGranted)
                Button(action: { request(kind) }) {
                    Label(actionTitle(for: kind, isGranted: isGranted), systemImage: actionIcon(for: kind, isGranted: isGranted))
                }
                .controlSize(.small)
                Button(action: { viewModel.openPermissionSettings(kind) }) {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Open System Settings")
            }
        }
    }

    private func statusBadge(_ isGranted: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isGranted ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(isGranted ? "Allowed" : "Needs Access")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isGranted ? .secondary : .primary)
        }
        .frame(width: 96, alignment: .leading)
    }

    private func actionTitle(for kind: PermissionKind, isGranted: Bool) -> LocalizedStringKey {
        if isGranted { return "Open" }
        switch kind {
        case .camera, .microphone:
            return "Request"
        case .screenRecording, .accessibility:
            return "Open"
        }
    }

    private func actionIcon(for kind: PermissionKind, isGranted: Bool) -> String {
        if isGranted { return "gearshape" }
        switch kind {
        case .camera, .microphone:
            return "hand.tap"
        case .screenRecording, .accessibility:
            return "gearshape"
        }
    }

    private func request(_ kind: PermissionKind) {
        Task { await viewModel.requestPermission(kind) }
    }

    private func refresh() {
        Task { await viewModel.refreshPermissions() }
    }
}
