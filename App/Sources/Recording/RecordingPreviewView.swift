import SwiftUI
import Observation

/// Reactive state for the recording preview window. The coordinator
/// flips `isSaving = true` when Save is clicked and feeds `saveProgress`
/// from the export pipeline. The view observes both via `@Observable`
/// tracking and re-renders the right column accordingly.
@MainActor
@Observable
final class RecordingPreviewState {
    var isSaving: Bool = false
    var saveProgress: Double = 0
}

struct RecordingPreviewView: View {
    let thumbnail: NSImage?
    let duration: String
    let fileSize: String
    let state: RecordingPreviewState
    let onCopy: () -> Void
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 200, maxHeight: 120)
                } else {
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 160, height: 100)
                        .overlay(
                            Image(systemName: "video.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white.opacity(0.5))
                        )
                }

                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.red)
                        Text(duration)
                    }
                    Text(fileSize)
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(8)

            // Right column: either action buttons (idle) or a progress
            // indicator (saving). We never display both at once so the user
            // can't accidentally double-click Save mid-export and end up
            // with two output files.
            Group {
                if state.isSaving {
                    savingOverlay
                } else {
                    VStack(spacing: 6) {
                        quickActionButton("Copy", systemImage: "doc.on.doc", action: onCopy)
                        quickActionButton("Save", systemImage: "square.and.arrow.down", action: onSave)
                    }
                }
            }
            .frame(width: 90)
            .padding(.trailing, 8)
            .padding(.vertical, 8)

            // Close button hidden during save — closing mid-export would
            // orphan the temp file with no UI to retry from.
            if !state.isSaving {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .padding(.top, 6)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }

    @ViewBuilder
    private var savingOverlay: some View {
        VStack(spacing: 6) {
            ProgressView(value: state.saveProgress)
                .progressViewStyle(.linear)
                .controlSize(.small)
                .tint(.accentColor)
            Text("Saving… \(Int(state.saveProgress * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func quickActionButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
