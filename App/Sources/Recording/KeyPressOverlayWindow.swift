// App/Sources/Recording/KeyPressOverlayWindow.swift
import AppKit
import SharedKit

/// Pure AppKit KeyCastr-style bezel window (no SwiftUI / NSHostingView).
///
/// Lessons from KeyCastr `KCDefaultVisualizerWindow` / `KCDefaultVisualizerBezelView`:
/// - Borderless, high window level, movable by background, clear chrome
/// - Append into the *current* bezel; ⌘/⌃ keystrokes start a new bezel
/// - After `keystrokeDelay` (~0.5s) idle, next key starts a new bezel
/// - Each bezel fades after `fadeDelay` (~2s)
/// - Resize via AppKit frames only (avoids SwiftUI display-cycle crashes)
///
/// Placement is relative to the active **display/area** recording frame so the HUD
/// stays inside the capture. Window-target recording is not supported for this overlay.
@MainActor
final class KeyPressOverlayWindow: NSPanel {
    private let settings: AppSettings
    /// Capture region in AppKit global coordinates (bottom-left origin).
    private let recordingFrame: CGRect
    private var currentBezel: KeyPressBezelView?
    private let margin: CGFloat = KeyPressOverlayPlacement.defaultMargin
    private let bezelSpacing: CGFloat = 10
    private let keystrokeDelay: TimeInterval = 0.5
    private let fadeDelay: TimeInterval = 2.0
    private let fadeDuration: TimeInterval = 0.2
    private let maxBezels = 6

    init(settings: AppSettings, recordingFrame: CGRect) {
        self.settings = settings
        self.recordingFrame = recordingFrame
        let size = KeyPressOverlayPlacement.defaultSize
        let origin = KeyPressOverlayPlacement.origin(
            savedOffsetX: settings.keyPressOverlayOffsetX,
            savedOffsetY: settings.keyPressOverlayOffsetY,
            recordingFrame: recordingFrame,
            size: size,
            margin: KeyPressOverlayPlacement.defaultMargin
        )
        let frame = KeyPressOverlayPlacement.clampedFrame(
            NSRect(origin: origin, size: size),
            in: recordingFrame,
            margin: KeyPressOverlayPlacement.defaultMargin
        )

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // KeyCastr uses NSScreenSaverWindowLevel so the HUD sits above almost everything.
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.isMovableByWindowBackground = true
        self.sharingType = .readWrite
        self.hidesOnDeactivate = false
        self.ignoresMouseEvents = false

        let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        self.contentView = root

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMoved),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        orderFrontRegardless()
    }

    func hideAndClose() {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        orderOut(nil)
        close()
    }

    /// - Parameters:
    ///   - text: formatted key label
    ///   - isCommand: KeyCastr “command-ish” (⌘/⌃) — forces a new bezel line
    func appendChip(_ text: String, isCommand: Bool = false) {
        // Do not trim with `.whitespaces` — a real space key is shown as "␣",
        // and accidental " " must not be wiped to empty.
        guard !text.isEmpty else { return }

        cancelLineBreak()
        if isCommand {
            abandonCurrentBezel()
        }

        if let currentBezel {
            currentBezel.append(text)
            currentBezel.scheduleFadeOut(delay: fadeDelay, duration: fadeDuration)
        } else {
            addNewBezel(text: text)
        }
        scheduleLineBreak()
        layoutBezels()
    }

    // Convenience for older call sites.
    func appendChip(_ text: String) {
        // Heuristic: labels starting with ⌃/⌘ are command-ish.
        let isCommand = text.contains("⌘") || text.contains("⌃")
        appendChip(text, isCommand: isCommand)
    }

    // MARK: - Bezel management (KeyCastr)

    private func addNewBezel(text: String) {
        guard let contentView else { return }
        let bezel = KeyPressBezelView(text: text)
        bezel.onFullyFaded = { [weak self, weak bezel] in
            guard let self, let bezel else { return }
            if self.currentBezel === bezel {
                self.currentBezel = nil
            }
            bezel.removeFromSuperview()
            self.layoutBezels()
        }
        contentView.addSubview(bezel)
        currentBezel = bezel
        bezel.scheduleFadeOut(delay: fadeDelay, duration: fadeDuration)

        // Drop oldest if too many.
        let bezels = contentView.subviews.compactMap { $0 as? KeyPressBezelView }
        if bezels.count > maxBezels {
            for old in bezels.prefix(bezels.count - maxBezels) {
                old.removeFromSuperview()
            }
        }
    }

    private func abandonCurrentBezel() {
        currentBezel = nil
    }

    private func scheduleLineBreak() {
        perform(#selector(abandonCurrentBezelObjC), with: nil, afterDelay: keystrokeDelay)
    }

    private func cancelLineBreak() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(abandonCurrentBezelObjC),
            object: nil
        )
    }

    @objc private func abandonCurrentBezelObjC() {
        abandonCurrentBezel()
    }

    private func layoutBezels() {
        guard let contentView else { return }
        let bezels = contentView.subviews.compactMap { $0 as? KeyPressBezelView }
        guard !bezels.isEmpty else {
            let size = KeyPressOverlayPlacement.defaultSize
            applyClampedFrame(CGRect(origin: frame.origin, size: size))
            return
        }

        var y: CGFloat = 0
        var maxWidth: CGFloat = 80
        // Stack upward from bottom (KeyCastr grows height as bezels stack).
        for bezel in bezels {
            bezel.sizeToFitLabel()
            let size = bezel.frame.size
            bezel.frame = NSRect(x: 0, y: y, width: size.width, height: size.height)
            maxWidth = max(maxWidth, size.width)
            y += size.height + bezelSpacing
        }

        let height = max(40, y - bezelSpacing)
        applyClampedFrame(CGRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: maxWidth,
            height: height
        ))
        contentView.frame = NSRect(origin: .zero, size: self.frame.size)
    }

    private func applyClampedFrame(_ proposed: CGRect) {
        let clamped = KeyPressOverlayPlacement.clampedFrame(
            proposed,
            in: recordingFrame,
            margin: margin
        )
        setFrame(clamped, display: true)
    }

    @objc private func handleMoved() {
        // Hard-clamp after drag so the HUD cannot leave the capture area.
        let clamped = KeyPressOverlayPlacement.clampedFrame(
            frame,
            in: recordingFrame,
            margin: margin
        )
        if clamped != frame {
            setFrame(clamped, display: true)
        }
        let off = KeyPressOverlayPlacement.offset(
            windowOrigin: clamped.origin,
            recordingFrame: recordingFrame
        )
        settings.keyPressOverlayOffsetX = off.x
        settings.keyPressOverlayOffsetY = off.y
    }
}

// MARK: - Bezel view (KeyCastr KCDefaultVisualizerBezelView simplified)

@MainActor
private final class KeyPressBezelView: NSView {
    var onFullyFaded: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var fadeWorkItem: DispatchWorkItem?

    init(text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        label.stringValue = text
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byClipping
        addSubview(label)
        sizeToFitLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func append(_ text: String) {
        label.stringValue += text
        sizeToFitLabel()
        needsDisplay = true
    }

    func sizeToFitLabel() {
        label.sizeToFit()
        let paddingH: CGFloat = 14
        let paddingV: CGFloat = 10
        let size = NSSize(
            width: label.fittingSize.width + paddingH * 2,
            height: label.fittingSize.height + paddingV * 2
        )
        setFrameSize(size)
        label.frame = NSRect(
            x: paddingH,
            y: paddingV,
            width: label.fittingSize.width,
            height: label.fittingSize.height
        )
    }

    func scheduleFadeOut(delay: TimeInterval, duration: TimeInterval) {
        fadeWorkItem?.cancel()
        alphaValue = 1
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                self.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.onFullyFaded?()
            })
        }
        fadeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
