import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SharedKit
import ExportKit

struct EditorPlaybackControls: View {
    @Bindable var coordinator: EditorCoordinator

    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause
            Button(action: { coordinator.togglePlayback() }) {
                Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])

            // Time display
            Text(coordinator.formatTime(coordinator.currentTime))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("/")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Text(coordinator.formatTime(coordinator.project.effectiveDuration))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)

            Spacer()

            if coordinator.isExporting {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(coordinator.exportStatusMessage ?? "Exporting…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ProgressView(value: coordinator.exportProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 160)
                            .controlSize(.small)
                        Text("\(Int(coordinator.exportProgress * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            } else {
                // Copy to clipboard
                Button(action: { exportToClipboard() }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Save to file
                Button(action: { exportToFile() }) {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "Recording.mp4"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                _ = try await coordinator.exportVideo(
                    format: .mp4,
                    quality: .maximum,
                    destination: url
                )
                // Close the editor window on successful export
                coordinator.closeEditor()
            } catch {
                await showExportError(error)
            }
        }
    }

    private func exportToClipboard() {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("\(UUID().uuidString).mp4")

        Task {
            do {
                let url = try await coordinator.exportVideo(
                    format: .mp4,
                    quality: .maximum,
                    destination: tempURL
                )
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
                // Close the editor window on successful export
                coordinator.closeEditor()
            } catch {
                await showExportError(error)
            }
        }
    }

    @MainActor
    private func showExportError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Export Failed")
        alert.informativeText = String(describing: error)
        alert.alertStyle = .warning
        alert.runModal()
    }
}
