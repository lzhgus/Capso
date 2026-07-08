// App/Sources/AnnotationEditor/AnnotationEditorWindow.swift
import AppKit
import SwiftUI
import AnnotationKit
import SharedKit

@MainActor
final class AnnotationEditorWindow: NSPanel {
    private let document: AnnotationDocument
    private let interactionState = AnnotationEditorInteractionState()
    private var alphaValueBeforeDrag: CGFloat?

    init(
        image: CGImage,
        anchorScreen: NSScreen? = nil,
        sourceAppName: String? = nil,
        sourceWindowTitle: String? = nil,
        captureDate: Date = Date(),
        screenshotOutputPreset: ScreenshotOutputPreset,
        screenshotFilenameTemplate: String,
        onSave: @escaping (CGImage) -> Void,
        onCopy: @escaping (CGImage) -> Void,
        onPin: @escaping (CGImage, CGRect?) -> Void,
        onClose: @escaping () -> Void
    ) {
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        self.document = AnnotationDocument(imageSize: CGSize(width: imgW, height: imgH))

        // Prefer the screen where the capture originated (the one the user was
        // focused on). Falling back to NSScreen.main unconditionally would
        // always open the editor on the primary display, even when the capture
        // came from a secondary one.
        let screen = anchorScreen ?? NSScreen.main ?? NSScreen.screens.first!
        let maxW = screen.visibleFrame.width * 0.8
        let maxH = screen.visibleFrame.height * 0.8
        let chromeH: CGFloat = 110

        let scale = min(1.0, min(maxW / imgW, (maxH - chromeH) / imgH))
        let winW = imgW * scale
        let winH = imgH * scale + chromeH

        // Center inside the target screen's visibleFrame. `visibleFrame` is
        // already in absolute desktop coordinates, so this puts the window on
        // the correct display even when that display isn't the primary one.
        let x = screen.visibleFrame.midX - winW / 2
        let y = screen.visibleFrame.midY - winH / 2

        let targetFrame = NSRect(x: x, y: y, width: winW, height: winH)

        super.init(
            contentRect: targetFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = "Annotate"
        self.isReleasedWhenClosed = false
        // Use .normal level so the window stays visible when app loses focus
        self.level = .normal
        // Keep the panel visible when the app loses focus — without this,
        // clicking another app's window hides the annotation editor.
        self.hidesOnDeactivate = false
        // Ensure tooltip tracking and key-window behaviour work correctly.
        self.becomesKeyOnlyIfNeeded = false
        self.acceptsMouseMovedEvents = true
        // AppKit re-applies window restoration + may snap `.titled` panels
        // back to main display on multi-monitor setups, ignoring the
        // contentRect passed to init. Disable restoration and explicitly
        // re-apply the target frame so we actually land on the right screen.
        self.isRestorable = false
        self.setFrame(targetFrame, display: false)

        let view = AnnotationEditorView(
            sourceImage: image,
            document: document,
            interactionState: interactionState,
            sourceAppName: sourceAppName,
            sourceWindowTitle: sourceWindowTitle,
            captureDate: captureDate,
            screenshotOutputPreset: screenshotOutputPreset,
            screenshotFilenameTemplate: screenshotFilenameTemplate,
            onSave: { [weak self] rendered in
                onSave(rendered)
                self?.close()
            },
            onCopy: { [weak self] rendered in
                onCopy(rendered)
                self?.close()
            },
            onPin: { [weak self] rendered in
                onPin(rendered, self?.frame)
                self?.close()
            },
            onDragStarted: { [weak self] in
                self?.hideDuringExternalDrag()
            },
            onDragEnded: { [weak self] in
                self?.showAfterExternalDrag()
            },
            onCancel: { [weak self] in
                onClose()
                self?.close()
            }
        )

        self.contentView = NSHostingView(rootView: view)
    }

    private func hideDuringExternalDrag() {
        guard alphaValueBeforeDrag == nil else { return }
        alphaValueBeforeDrag = alphaValue
        alphaValue = 0
        ignoresMouseEvents = true
    }

    private func showAfterExternalDrag() {
        alphaValue = alphaValueBeforeDrag ?? 1
        alphaValueBeforeDrag = nil
        ignoresMouseEvents = false
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if interactionState.shouldSuppressCopyShortcut(for: event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           interactionState.shouldSuppressCopyShortcut(for: event) {
            return
        }
        super.sendEvent(event)
    }
}
