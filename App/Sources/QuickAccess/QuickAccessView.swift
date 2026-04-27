// App/Sources/QuickAccess/QuickAccessView.swift
import SwiftUI
import AppKit
import CaptureKit
import SharedKit
import ShareKit

struct QuickAccessView: View {
    let thumbnail: NSImage
    let captureImage: CGImage           // used for cloud upload (temp-file write)
    let dimensions: String           // e.g. "1920×1080"
    let capturedAt: Date
    let targetLanguageDisplay: String?  // e.g. "Simplified Chinese"
    let shareCoordinator: ShareCoordinator?
    /// Called with the public URL string when a cloud upload succeeds.
    /// Use this to persist the URL to the history entry.
    let onUploadSucceeded: ((String) -> Void)?
    let onCopy: () -> Void
    let onSave: () -> Void
    let onAnnotate: () -> Void
    let onOCR: () -> Void
    let onTranslate: () -> Void
    let onPin: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var hoveredAction: HoverAction?
    @State private var visualState: PanelUploadState = .idle
    @FocusState private var isFocused: Bool

    private enum PanelUploadState: Equatable {
        case idle
        case uploading
        case succeeded
        case failed(ShareError)
    }

    private enum HoverAction: Hashable {
        case copy, save, annotate, ocr, translate, pin, upload, linkCopied
    }

    private var isRevealed: Bool { isHovering || isFocused }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        VStack(spacing: 8) {
            thumbnailFrame

            // Caption at rest / Chrome on hover — crossfade in the same slot
            ZStack {
                captionRow
                    .opacity(isRevealed ? 0 : 1)
                chromeStrip
                    .opacity(isRevealed ? 1 : 0)
            }
            .frame(height: 50)
        }
        .padding(8)
        .background(hiddenEscapeButton)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .offset(y: isRevealed ? -2 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.26), value: isRevealed)
        .onHover { isHovering = $0 }
        .focusable()
        .focused($isFocused)
        .overlay(alignment: .bottom) {
            if case .failed(let err) = visualState {
                FailureToast(error: err) {
                    Task { await performUpload() }  // retry
                } onDismiss: {
                    visualState = .idle
                }
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Thumbnail

    private var thumbnailFrame: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 268, maxHeight: 116)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black.opacity(0.25), lineWidth: 0.5)
                )

            if isRevealed {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.regularMaterial))
                }
                .buttonStyle(.plain)
                .padding(6)
                .transition(.opacity)
                .help("Close")
            }
        }
    }

    // MARK: - Caption (at rest)

    private var captionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Capture,")
                .font(.system(size: 14, design: .serif).italic())
                .foregroundStyle(.primary)
            Spacer()
            Text(metaLine)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .tracking(0.6)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 6)
    }

    private var metaLine: String {
        "\(dimensions) · \(relativeTime)"
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: capturedAt, relativeTo: Date())
    }

    // MARK: - Chrome (revealed on hover/focus)

    private var chromeStrip: some View {
        VStack(spacing: 4) {
            contextLine
            toolbar
        }
    }

    private var contextLine: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(contextTitle)
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(.primary)
            Spacer()
            contextHintView
        }
        .padding(.horizontal, 4)
        .frame(height: 20)
    }

    private var contextTitle: String {
        guard let action = hoveredAction else { return "Quick Access" }
        return label(action)
    }

    /// Right-aligned hint for the hovered action: a keycap-style pill
    /// showing the shortcut (⌘S, ⌘⇧T, …) plus — for Translate — a subtle
    /// suffix naming the target language.
    @ViewBuilder
    private var contextHintView: some View {
        HStack(spacing: 5) {
            if let key = hoveredShortcutKey {
                ShortcutKeyPill(text: key)
            }
            if let suffix = hoveredHintSuffix {
                Text(suffix)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hoveredShortcutKey: String? {
        guard let action = hoveredAction else { return nil }
        switch action {
        case .copy:      return "⌘C"
        case .save:      return "⌘S"
        case .annotate:  return "⌘E"
        case .ocr:       return "⌘⇧O"
        case .translate: return "⌘⇧T"
        case .pin:       return "⌘P"
        case .upload, .linkCopied: return nil
        }
    }

    private var hoveredHintSuffix: String? {
        guard hoveredAction == .translate,
              let lang = targetLanguageDisplay, !lang.isEmpty else { return nil }
        return "→ \(lang)"
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            toolButton(.copy, icon: "doc.on.doc", action: onCopy)
            toolButton(.save, icon: "square.and.arrow.down", action: onSave)
            if shareCoordinator != nil {
                toolDivider
                uploadButton
            }
            toolDivider
            toolButton(.annotate, icon: "pencil.tip.crop.circle", action: onAnnotate)
            toolDivider
            toolButton(.ocr, icon: "text.viewfinder", action: onOCR)
            toolButton(.translate, icon: "character.bubble", action: onTranslate)
            toolDivider
            toolButton(.pin, icon: "pin", action: onPin)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Quick Access actions"))
    }

    @ViewBuilder
    private var uploadButton: some View {
        if shareCoordinator != nil {
            switch visualState {
            case .idle, .failed:
                toolButton(
                    .upload,
                    icon: "icloud.and.arrow.up",
                    action: { Task { await performUpload() } }
                )
            case .uploading:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 26)  // matches toolButton height
            case .succeeded:
                toolButton(.linkCopied, icon: "checkmark.circle.fill", action: {})
                    .foregroundStyle(.green)
                    .disabled(true)
            }
        }
    }

    private func performUpload() async {
        guard let coord = shareCoordinator else { return }
        let image = captureImage  // capture into local for the detached closure

        // Encode + write off main actor — large PNGs block UI for hundreds of ms otherwise
        let tempURL: URL? = await Task.detached(priority: .userInitiated) { () -> URL? in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("png")
            guard let data = ImageUtilities.pngData(from: image) else { return nil }
            do {
                try data.write(to: url)
                return url
            } catch {
                return nil
            }
        }.value

        guard let tempURL else {
            // Encode/write failed — show as failure
            visualState = .failed(.unknown("Failed to encode capture for upload"))
            return
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        visualState = .uploading
        do {
            let cloudURL = try await coord.upload(file: tempURL, contentType: "image/png")
            onUploadSucceeded?(cloudURL.absoluteString)
            visualState = .succeeded
            try? await Task.sleep(for: .seconds(3))
            if case .succeeded = visualState {
                visualState = .idle
            }
        } catch let err as ShareError {
            visualState = .failed(err)
        } catch {
            visualState = .failed(.unknown(error.localizedDescription))
        }
    }

    @ViewBuilder
    private func toolButton(_ kind: HoverAction, icon: String, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hoveredAction == kind ? Color.primary.opacity(0.10) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hoveredAction = $0 ? kind : nil }
        .help(Text(label(kind)))
        .accessibilityLabel(Text(label(kind)))
        .accessibilityHint(Text(hintForAccessibility(kind)))

        // Apply local keyboard shortcut so pressing the hinted key activates the action
        // whenever the Quick Access panel is key. `.nonactivatingPanel` + canBecomeKey=true
        // means shortcuts work while the panel is frontmost in our app, without stealing
        // focus from other apps.
        if let shortcut = shortcut(for: kind) {
            button.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            button
        }
    }

    private func shortcut(for kind: HoverAction) -> (key: KeyEquivalent, modifiers: EventModifiers)? {
        switch kind {
        case .copy:      return ("c", [.command])
        case .save:      return ("s", [.command])
        case .annotate:  return ("e", [.command])
        case .ocr:       return ("o", [.command, .shift])
        case .translate: return ("t", [.command, .shift])
        case .pin:       return ("p", [.command])
        case .upload, .linkCopied: return nil
        }
    }

    private var hiddenEscapeButton: some View {
        Button(action: onClose) { EmptyView() }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
    }

    private var toolDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 14)
    }

    private func label(_ kind: HoverAction) -> String {
        switch kind {
        case .copy: return String(localized: "Copy")
        case .save: return String(localized: "Save")
        case .annotate: return String(localized: "Annotate")
        case .ocr: return String(localized: "Extract Text")
        case .translate: return String(localized: "Translate")
        case .pin: return String(localized: "Pin")
        case .upload: return String(localized: "Upload to Cloud")
        case .linkCopied: return String(localized: "Link Copied!")
        }
    }

    private func hintForAccessibility(_ kind: HoverAction) -> String {
        switch kind {
        case .copy: return String(localized: "Copy to clipboard")
        case .save: return String(localized: "Save screenshot")
        case .annotate: return String(localized: "Open annotation editor")
        case .ocr: return String(localized: "Extract text from screenshot")
        case .translate: return String(localized: "Translate text in screenshot")
        case .pin: return String(localized: "Pin to screen")
        case .upload: return String(localized: "Upload screenshot to cloud and copy link")
        case .linkCopied: return String(localized: "Link has been copied to clipboard")
        }
    }
}

// MARK: - Failure toast

private struct FailureToast: View {
    let error: ShareError
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12))
            Button(String(localized: "Retry"), action: onRetry)
                .controlSize(.small)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    private var message: String {
        switch error {
        case .invalidCredentials:
            return String(localized: "Cloud credentials are invalid. Open Settings to fix.")
        case .network(let underlying):
            return String(localized: "Upload failed — network error: \(underlying)")
        case .quotaExceeded:
            return String(localized: "Cloud quota exceeded.")
        case .publicAccessUnreachable:
            return String(localized: "Upload OK but public URL unreachable. Check bucket settings.")
        case .invalidURLPrefix(let reason):
            return String(localized: "Cloud URL prefix is invalid: \(reason)")
        case .notConfigured:
            return String(localized: "Cloud sharing is not configured.")
        case .unknown(let detail):
            return String(localized: "Upload failed: \(detail)")
        }
    }
}

// MARK: - Shortcut keycap pill

/// Renders a keyboard shortcut (e.g. "⌘S", "⌘⇧T") as a compact, slightly
/// tinted pill — visually distinct from surrounding secondary text, which at
/// 9pt/secondary on ultraThinMaterial was too dim to read at a glance.
private struct ShortcutKeyPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.5)  // breathing room between modifier + key glyphs
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}
