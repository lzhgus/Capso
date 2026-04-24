// App/Sources/Translation/TranslationResultWindow.swift
import AppKit
import SwiftUI
import SharedKit
import OCRKit
import TranslationKit

@MainActor
final class TranslationResultWindow: NSPanel {
    private let settings: AppSettings
    private let regions: [TextRegion]
    private let target: String
    private var dismissTimer: Timer?

    var onClose: (() -> Void)?
    var onPinChanged: ((Bool) -> Void)?
    var onChangeLanguage: (() -> Void)?

    override var canBecomeKey: Bool { true }

    init(
        regions: [TextRegion],
        target: String,
        settings: AppSettings,
        anchor: NSRect?,
        anchorScreen: NSScreen?
    ) {
        self.regions = regions
        self.target = target
        self.settings = settings

        // Fixed window size matching the SwiftUI view's `.frame(width: 360, height: 480)`.
        // No auto-resize — internal ScrollView handles overflow.
        let frame = Self.positionedFrame(
            size: NSSize(width: 360, height: 480),
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

    func show() {
        let view = TranslationResultView(
            regions: regions,
            target: target,
            autoCopy: settings.translationAutoCopy,
            onClose:          { [weak self] in self?.onClose?() },
            onPinChanged:     { [weak self] isPinned in self?.onPinChanged?(isPinned) },
            onChangeLanguage: { [weak self] in self?.onChangeLanguage?() }
        )
        // Plain NSHostingView (no NSHostingController sizingOptions) — prevents
        // the window <=> SwiftUI layout feedback loop that was causing stack overflow.
        contentView = NSHostingView(rootView: view)

        makeKeyAndOrderFront(nil)

        if settings.translationAutoDismiss == .afterDelay {
            dismissTimer = Timer.scheduledTimer(
                withTimeInterval: settings.translationAutoDismissDelay,
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor in self?.onClose?() }
            }
        }
    }

    override func close() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        super.close()
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
