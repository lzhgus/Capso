// App/Sources/AnnotationEditor/AnnotationEditorWindow.swift
import AppKit
import SwiftUI
import AnnotationKit
import SharedKit

@MainActor
final class AnnotationEditorWindow: NSPanel, NSWindowDelegate {
    /// Internal (not private) so tests can assert on document state.
    let document: AnnotationDocument
    /// Frame computed from image pixels + anchor screen. Re-applied in `show()`
    /// because AppKit can still nudge `.titled` panels after init.
    private let preferredFrame: NSRect
    private var alphaValueBeforeDrag: CGFloat?
    private let onCloseCallback: () -> Void
    /// Injectable so tests never present a real modal alert.
    var confirmDiscard: () -> Bool = { false }

    private static let style: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]
    private static let chromeHeight: CGFloat = 110

    init(
        image: CGImage,
        anchorScreen: NSScreen? = nil,
        sourceAppName: String? = nil,
        sourceWindowTitle: String? = nil,
        captureDate: Date = Date(),
        screenshotOutputPreset: ScreenshotOutputPreset,
        screenshotFilenameTemplate: String,
        onSave: @escaping (CGImage) -> Bool,
        onCopy: @escaping (CGImage) -> Void,
        onPin: @escaping (CGImage, CGRect?) -> Void,
        onClose: @escaping () -> Void
    ) {
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        self.document = AnnotationDocument(imageSize: CGSize(width: imgW, height: imgH))
        self.onCloseCallback = onClose

        // Prefer the screen where the capture originated (the one the user was
        // focused on). Falling back to NSScreen.main unconditionally would
        // always open the editor on the primary display, even when the capture
        // came from a secondary one.
        let screen = anchorScreen ?? NSScreen.main ?? NSScreen.screens.first!
        let contentSize = AnnotationEditorWindowGeometry.contentSize(
            imagePixelSize: CGSize(width: imgW, height: imgH),
            backingScaleFactor: screen.backingScaleFactor,
            visibleSize: screen.visibleFrame.size,
            chromeHeight: Self.chromeHeight
        )
        // `contentSize` is the content-area size. Convert to a full window frame
        // (including titlebar) before centering so the visible chrome is what
        // ends up mid-screen, not just the content rect.
        let contentRect = NSRect(origin: .zero, size: contentSize)
        let frameSize = NSWindow.frameRect(forContentRect: contentRect, styleMask: Self.style).size
        let targetFrame = AnnotationEditorWindowGeometry.centeredFrame(
            size: frameSize,
            in: screen.visibleFrame
        )
        self.preferredFrame = targetFrame

        super.init(
            contentRect: NSWindow.contentRect(forFrameRect: targetFrame, styleMask: Self.style),
            styleMask: Self.style,
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
        // contentRect passed to init. Disable restoration and re-apply the
        // target frame after installing content (hosting views can resize
        // the window) so we actually land centered on the right screen.
        self.isRestorable = false

        self.confirmDiscard = { [weak self] in
            AnnotationEditorCloseGuard.presentDiscardAlert(above: self)
        }
        self.delegate = self

        let view = AnnotationEditorView(
            sourceImage: image,
            document: document,
            sourceAppName: sourceAppName,
            sourceWindowTitle: sourceWindowTitle,
            captureDate: captureDate,
            screenshotOutputPreset: screenshotOutputPreset,
            screenshotFilenameTemplate: screenshotFilenameTemplate,
            onSave: { [weak self] rendered in
                // `onSave` may cancel (e.g. the user dismisses an "overwrite
                // vs. save a copy" prompt) — only close the window when a
                // save actually happened, otherwise the editor should stay open.
                guard onSave(rendered) else { return }
                MainActor.assumeIsolated {
                    self?.close()
                }
            },
            onCopy: { [weak self] rendered in
                onCopy(rendered)
                MainActor.assumeIsolated {
                    self?.close()
                }
            },
            onPin: { [weak self] rendered in
                MainActor.assumeIsolated {
                    onPin(rendered, self?.frame)
                    self?.close()
                }
            },
            onDragStarted: { [weak self] in
                MainActor.assumeIsolated {
                    self?.hideDuringExternalDrag()
                }
            },
            onDragEnded: { [weak self] in
                MainActor.assumeIsolated {
                    self?.showAfterExternalDrag()
                }
            },
            onCancel: { [weak self] in
                self?.requestClose()
            }
        )

        self.contentView = NSHostingView(rootView: view)
        // Hosting the SwiftUI tree can resize the panel; re-assert the
        // centered frame computed from the capture's pixel size.
        self.setFrame(targetFrame, display: false)
    }

    /// Closes if there's nothing to lose, otherwise confirms with the user
    /// first. Used by the toolbar's Close button and the red titlebar button
    /// — never by Save/Copy/Pin, which call `close()` directly and should
    /// never prompt. Esc never reaches this; see `AnnotationEscapePolicy`.
    func requestClose() {
        guard AnnotationEditorCloseGuard.shouldClose(
            hasUnsavedChanges: document.hasUnsavedChanges,
            confirmDiscard: confirmDiscard
        ) else { return }
        close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        AnnotationEditorCloseGuard.shouldClose(
            hasUnsavedChanges: document.hasUnsavedChanges,
            confirmDiscard: confirmDiscard
        )
    }

    func windowWillClose(_ notification: Notification) {
        onCloseCallback()
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
        // Re-apply the centered frame on show. Some AppKit path repositions
        // titled panels between init and first presentation, which left the
        // Annotate window off-center (issue #236).
        setFrame(preferredFrame, display: false)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if routeAnnotationClipboardShortcutToCanvas(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           routeAnnotationClipboardShortcutToCanvas(event) {
            return
        }
        super.sendEvent(event)
    }
}
