import SwiftUI
import EditorKit

struct RecordingEditorView: View {
    @Bindable var coordinator: EditorCoordinator

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ZStack {
                        EditorPreviewView(coordinator: coordinator)
                            .padding(16)
                            .animation(Animation.easeInOut(duration: 0.2), value: coordinator.project.backgroundStyle.enabled)
                            .animation(Animation.easeInOut(duration: 0.15), value: coordinator.project.backgroundStyle.padding)
                            .animation(Animation.easeInOut(duration: 0.15), value: coordinator.project.backgroundStyle.cornerRadius)
                            .animation(Animation.easeInOut(duration: 0.15), value: coordinator.project.backgroundStyle.shadowEnabled)

                        if coordinator.isExporting {
                            exportOverlay
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                EditorSettingsPanel(coordinator: coordinator)
                    .frame(width: 260)
            }
            .frame(maxHeight: .infinity)

            Divider()

            VStack(spacing: 8) {
                EditorPlaybackControls(coordinator: coordinator)
                EditorTimelineView(coordinator: coordinator)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: 180)
        }
    }

    private var exportOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.24))
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView(value: coordinator.exportProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 220)

                Text(coordinator.exportStatusMessage ?? "Exporting…")
                    .font(.system(size: 13, weight: .medium))

                Text("The editor will close when the export is finished.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        }
        .transition(.opacity)
    }
}
