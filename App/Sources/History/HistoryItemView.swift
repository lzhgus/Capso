// App/Sources/History/HistoryItemView.swift
import SwiftUI
import HistoryKit
import ShareKit

struct HistoryItemView: View {
    let entry: HistoryEntry
    let coordinator: HistoryCoordinator
    @State private var isHovered = false
    @State private var thumbnailImage: NSImage?

    // Cloud upload state for this item
    @State private var isUploading = false
    @State private var showCloudFailureToast = false
    @State private var cloudFailureMessage = ""

    // Delete confirmation
    @State private var showDeleteConfirm = false

    private var modeBadge: (String, Color) {
        switch entry.captureMode {
        case .area: ("Area", .blue)
        case .fullscreen: ("Full", .blue)
        case .window: ("Window", .blue)
        case .recording: ("Video", .red)
        case .gif: ("GIF", .orange)
        }
    }

    private var timeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: entry.createdAt, relativeTo: Date())
    }

    private var dimensionString: String {
        "\(entry.imageWidth) × \(entry.imageHeight)"
    }

    private var displayName: String {
        if let name = entry.sourceAppName, !name.isEmpty {
            return name
        }
        switch entry.captureMode {
        case .area: return String(localized: "Area Capture")
        case .fullscreen: return String(localized: "Fullscreen")
        case .window: return String(localized: "Window")
        case .recording: return String(localized: "Recording")
        case .gif: return String(localized: "GIF")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)

                // Mode badge
                let (label, color) = modeBadge
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.3)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(6)

                // Hover action buttons
                if isHovered {
                    HStack(spacing: 4) {
                        actionButton("doc.on.doc") { coordinator.copyToClipboard(entry) }
                        actionButton("square.and.arrow.down") { coordinator.saveToFile(entry) }
                        cloudActionButton
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                // Cloud upload failure toast overlay
                if showCloudFailureToast {
                    cloudFailureToast
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 4)
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(isHovered ? 0.1 : 0.04), lineWidth: 0.5)
            )

            // Info row
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(displayName)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    // Persistent cloud indicator when URL is saved
                    if entry.cloudURL != nil {
                        Image(systemName: "checkmark.icloud.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.blue.opacity(0.7))
                            .help(String(localized: "Uploaded to cloud"))
                    }
                }

                HStack(spacing: 4) {
                    Text(timeString)
                    Circle()
                        .fill(.tertiary)
                        .frame(width: 2, height: 2)
                    Text(dimensionString)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .background(.white.opacity(isHovered ? 0.06 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(isHovered ? 0.1 : 0.04), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isHovered ? 0.2 : 0), radius: 8, y: 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear { loadThumbnail() }
        .contextMenu { contextMenu }
        .sheet(isPresented: $showDeleteConfirm) {
            DeleteConfirmSheet(
                entry: entry,
                onDelete: { alsoDeleteCloud in
                    showDeleteConfirm = false
                    Task {
                        if alsoDeleteCloud {
                            await coordinator.deleteCloudCopy(for: entry)
                        }
                        coordinator.deleteEntry(entry)
                    }
                },
                onCancel: { showDeleteConfirm = false }
            )
        }
    }

    // MARK: - Cloud Action Button

    @ViewBuilder
    private var cloudActionButton: some View {
        if let cloudURL = entry.cloudURL {
            // Already uploaded — show "Copy link" button
            actionButton("link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cloudURL, forType: .string)
            }
            .help(String(localized: "Copy cloud link"))
        } else if coordinator.shareCoordinator != nil {
            // Not uploaded, cloud configured — show upload button
            if isUploading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 30, height: 30)
                    .background(.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                actionButton("icloud.and.arrow.up") {
                    Task { await performUpload() }
                }
                .help(String(localized: "Upload to cloud"))
            }
        }
        // No cloud configured → no cloud button
    }

    private func performUpload() async {
        guard !isUploading else { return }
        isUploading = true
        showCloudFailureToast = false
        do {
            _ = try await coordinator.uploadEntry(entry)
        } catch let err as ShareError {
            cloudFailureMessage = shareErrorMessage(err)
            showCloudFailureToast = true
            Task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { showCloudFailureToast = false }
            }
        } catch {
            cloudFailureMessage = error.localizedDescription
            showCloudFailureToast = true
            Task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { showCloudFailureToast = false }
            }
        }
        isUploading = false
    }

    private func shareErrorMessage(_ err: ShareError) -> String {
        switch err {
        case .invalidCredentials: return String(localized: "Cloud credentials are invalid.")
        case .network(let u): return String(localized: "Network error: \(u)")
        case .quotaExceeded: return String(localized: "Cloud quota exceeded.")
        case .publicAccessUnreachable: return String(localized: "Upload OK but public URL unreachable.")
        case .invalidURLPrefix(let r): return String(localized: "Invalid URL prefix: \(r)")
        case .notConfigured: return String(localized: "Cloud sharing is not configured.")
        case .unknown(let d): return String(localized: "Upload failed: \(d)")
        }
    }

    // MARK: - Cloud Failure Toast

    private var cloudFailureToast: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
            Text(cloudFailureMessage)
                .font(.system(size: 10))
                .lineLimit(2)
            Button {
                withAnimation { showCloudFailureToast = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 4)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailImage {
            Image(nsImage: thumbnailImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Rectangle()
                .fill(.quaternary.opacity(0.3))
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(.quaternary)
                }
        }
    }

    private func actionButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Copy to Clipboard") { coordinator.copyToClipboard(entry) }
        Button("Save to...") { coordinator.saveToFile(entry) }

        if let cloudURL = entry.cloudURL {
            Button(String(localized: "Copy Cloud Link")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cloudURL, forType: .string)
            }
        } else if coordinator.shareCoordinator != nil {
            Button(String(localized: "Upload to Cloud")) {
                Task { await performUpload() }
            }
        }

        Divider()
        Button("Show in Finder") { coordinator.showInFinder(entry) }
        Divider()
        Button("Delete from History", role: .destructive) {
            showDeleteConfirm = true
        }
    }

    private func loadThumbnail() {
        guard let url = coordinator.thumbnailURL(for: entry) else { return }
        thumbnailImage = NSImage(contentsOf: url)
    }
}

// MARK: - Delete Confirmation Sheet

/// A custom sheet used for delete confirmation because SwiftUI's `.alert`
/// does not support `Toggle` in its action builder.
/// Shows a "Also delete from cloud" toggle only when the entry has a cloud URL.
private struct DeleteConfirmSheet: View {
    let entry: HistoryEntry
    let onDelete: (Bool) -> Void
    let onCancel: () -> Void

    @State private var alsoDeleteFromCloud: Bool

    init(entry: HistoryEntry, onDelete: @escaping (Bool) -> Void, onCancel: @escaping () -> Void) {
        self.entry = entry
        self.onDelete = onDelete
        self.onCancel = onCancel
        // Default to true (delete cloud copy) if one exists
        _alsoDeleteFromCloud = State(initialValue: entry.cloudURL != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Delete capture?")
                    .font(.system(size: 14, weight: .semibold))

                if entry.cloudURL != nil {
                    Text("This will remove the capture from this Mac. You can also remove the cloud copy.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text("This will remove the capture from this Mac.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if entry.cloudURL != nil {
                Toggle(isOn: $alsoDeleteFromCloud) {
                    Text("Also delete from cloud")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
            }

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.defaultAction)

                Button(String(localized: "Delete")) {
                    onDelete(alsoDeleteFromCloud)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .foregroundStyle(.red)
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.85))
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
