// App/Sources/Translation/TranslationResultWindow.swift
import AppKit
import SwiftUI
import SharedKit
import OCRKit
import TranslationKit

@MainActor
final class TranslationResultWindow: NSPanel {
    private static let cardWidth: CGFloat = 420
    private static let recognizingHeight: CGFloat = 160

    private let settings: AppSettings
    private let anchor: NSRect?
    private let anchorScreen: NSScreen?
    private var dismissTimer: Timer?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var isPinned = false
    private var translationCompleted = false
    private var lastProgrammaticFrame: NSRect?

    var onClose: (() -> Void)?
    var onPinChanged: ((Bool) -> Void)?
    var onChangeLanguage: (() -> Void)?

    override var canBecomeKey: Bool { true }

    init(
        settings: AppSettings,
        anchor: NSRect?,
        anchorScreen: NSScreen?
    ) {
        self.settings = settings
        self.anchor = anchor
        self.anchorScreen = anchorScreen

        let frame = Self.positionedFrame(
            size: NSSize(width: Self.cardWidth, height: Self.recognizingHeight),
            anchor: anchor,
            anchorScreen: anchorScreen,
            position: settings.translationCardPosition
        )

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .transient]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    func showRecognizing() {
        translationCompleted = false
        disarmAutoDismiss()
        resize(height: Self.recognizingHeight)
        contentView = NSHostingView(rootView: TranslationRecognizingView(
            onClose: { [weak self] in self?.onClose?() }
        ))
        makeKeyAndOrderFront(nil)
    }

    func showTranslation(
        regions: [TextRegion],
        target: String,
        provider: TranslationProviderKind,
        providerConfig: TranslationProviderConfiguration
    ) {
        translationCompleted = false
        disarmAutoDismiss()
        let sourceText = TranslationTextLayout.compose(regions.map {
            TranslationTextLine(text: $0.text, frame: $0.boundingBox)
        })
        let height = Self.preferredHeight(for: sourceText)
        resize(height: height)
        let view = TranslationResultView(
            regions: regions,
            target: target,
            provider: provider,
            providerConfig: providerConfig,
            autoCopy: settings.translationAutoCopy,
            showOriginal: settings.translationShowOriginal,
            onClose:          { [weak self] in self?.onClose?() },
            onPinChanged:     { [weak self] isPinned in self?.onPinChanged?(isPinned) },
            onChangeLanguage: { [weak self] in self?.onChangeLanguage?() },
            onTranslationCompleted: { [weak self] in self?.translationDidComplete() },
            height: height
        )
        // Plain NSHostingView (no NSHostingController sizingOptions) — prevents
        // the window <=> SwiftUI layout feedback loop that was causing stack overflow.
        contentView = NSHostingView(rootView: view)

        makeKeyAndOrderFront(nil)
    }

    static func preferredHeight(for text: String) -> CGFloat {
        let estimatedLineCount = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { count, line in
                count + max(1, Int(ceil(Double(line.count) / 48)))
            }
        let estimatedHeight = 130 + CGFloat(estimatedLineCount) * 22
        return min(520, max(240, estimatedHeight))
    }

    static func frameAfterResize(
        currentFrame: NSRect,
        lastProgrammaticFrame: NSRect?,
        preferredFrame: NSRect
    ) -> NSRect {
        guard let lastProgrammaticFrame,
              abs(currentFrame.minX - lastProgrammaticFrame.minX) > 0.5
                || abs(currentFrame.minY - lastProgrammaticFrame.minY) > 0.5 else {
            return preferredFrame
        }
        return NSRect(
            x: currentFrame.minX,
            y: currentFrame.maxY - preferredFrame.height,
            width: preferredFrame.width,
            height: preferredFrame.height
        )
    }

    func translationDidComplete() {
        guard !translationCompleted else { return }
        translationCompleted = true
        armAutoDismissIfNeeded()
    }

    private func armAutoDismissIfNeeded() {
        guard translationCompleted, !isPinned else { return }
        disarmAutoDismiss()
        if settings.translationAutoDismiss == .afterDelay {
            dismissTimer = Timer.scheduledTimer(
                withTimeInterval: settings.translationAutoDismissDelay,
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.translationCompleted, !self.isPinned else { return }
                    self.onClose?()
                }
            }
        }
        if settings.translationAutoDismiss == .clickOutside {
            installClickOutsideMonitors()
        }
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        if pinned {
            disarmAutoDismiss()
        } else {
            armAutoDismissIfNeeded()
        }
    }

    override func close() {
        disarmAutoDismiss()
        super.close()
    }

    private func disarmAutoDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        removeClickOutsideMonitors()
    }

    private func resize(height: CGFloat) {
        let preferredFrame = Self.positionedFrame(
            size: NSSize(width: Self.cardWidth, height: height),
            anchor: anchor,
            anchorScreen: anchorScreen,
            position: settings.translationCardPosition
        )
        let resizedFrame = Self.frameAfterResize(
            currentFrame: frame,
            lastProgrammaticFrame: lastProgrammaticFrame,
            preferredFrame: preferredFrame
        )
        let targetScreen = anchorScreen ?? screen ?? NSScreen.main ?? NSScreen.screens.first!
        let constrainedFrame = constrainFrameRect(resizedFrame, to: targetScreen)
        setFrame(constrainedFrame, display: true)
        lastProgrammaticFrame = constrainedFrame
    }

    private func installClickOutsideMonitors() {
        removeClickOutsideMonitors()
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if !self.isPinned && event.window !== self {
                self.onClose?()
            }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.isPinned else { return }
            self.onClose?()
        }
    }

    private func removeClickOutsideMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private static func positionedFrame(
        size: NSSize,
        anchor: NSRect?,
        anchorScreen: NSScreen?,
        position: TranslationCardPosition
    ) -> NSRect {
        let screen = anchorScreen ?? NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        let padding: CGFloat = 12

        func centered() -> NSRect {
            NSRect(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

        switch position {
        case .centerScreen, .rememberLast:
            return centered()

        case .belowSelection:
            guard let anchor else { return centered() }
            let rawX = anchor.midX - size.width / 2
            let x = max(visible.minX + padding, min(visible.maxX - size.width - padding, rawX))
            let belowY = anchor.minY - size.height - padding
            if belowY >= visible.minY + padding {
                return NSRect(x: x, y: belowY, width: size.width, height: size.height)
            }
            let aboveY = anchor.maxY + padding
            if aboveY + size.height <= visible.maxY - padding {
                return NSRect(x: x, y: aboveY, width: size.width, height: size.height)
            }
            return centered()
        }
    }
}

private struct TranslationRecognizingView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Circle()
                        .fill(Color.red.opacity(0.9))
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Close")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Recognizing text…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 24)
        }
        .frame(width: 420, height: 160)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}
