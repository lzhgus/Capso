// App/Sources/AnnotationEditor/AnnotationEditorWindow.swift
import AppKit
import SwiftUI
import AnnotationKit
import SharedKit

@MainActor
final class AnnotationEditorWindow: NSPanel, NSWindowDelegate {
    /// Internal (not private) so tests can assert on document state.
    let document: AnnotationDocument
    /// Centered frame for this capture, resolved once the SwiftUI tree's own
    /// minimum size is known. Re-applied on first `show()` because AppKit can
    /// still nudge `.titled` panels between init and presentation.
    private var preferredFrame: NSRect
    /// `visibleFrame` of the screen the editor was sized against.
    private let anchorVisibleFrame: NSRect
    private var hasAppliedPreferredFrame = false
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
        screenshotOutput: ScreenshotOutputOptions,
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
        let visibleFrame = screen.visibleFrame
        let imageContentSize = AnnotationEditorWindowGeometry.contentSize(
            imagePixelSize: CGSize(width: imgW, height: imgH),
            backingScaleFactor: screen.backingScaleFactor,
            visibleSize: visibleFrame.size,
            chromeHeight: Self.chromeHeight
        )
        // Provisional frame. The final one is resolved after the SwiftUI tree is
        // installed, once it can report how much width the toolbar needs.
        let initialFrame = Self.centeredFrame(
            contentSize: imageContentSize,
            in: visibleFrame
        )
        self.anchorVisibleFrame = visibleFrame
        self.preferredFrame = initialFrame

        super.init(
            contentRect: Self.contentRect(forFrameRect: initialFrame, styleMask: Self.style),
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
        // contentRect passed to init. Disable restoration so the frame we
        // compute is the one that sticks.
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
            screenshotOutput: screenshotOutput,
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

        let hostingView = NSHostingView(rootView: view)
        self.contentView = hostingView
        resizeAndCenter(preferredContentSize: imageContentSize, hostingView: hostingView)
    }

    /// Grows the window to whatever the SwiftUI tree wants before centering it.
    ///
    /// The toolbar is a row of fixed-width controls, so the hosting view has a
    /// wide fitting size that AppKit applies on a later runloop pass — widening
    /// the window from its existing origin and dragging it off-center. Sizing
    /// to it up front means the frame we center is the frame that survives
    /// (issue #236).
    private func resizeAndCenter(preferredContentSize: CGSize, hostingView: NSHostingView<AnnotationEditorView>) {
        // `contentMinSize` is still zero at this point; the hosting view's own
        // fitting size is what AppKit will eventually derive the window's
        // preferred width from.
        hostingView.layoutSubtreeIfNeeded()
        let resolvedContentSize = AnnotationEditorWindowGeometry.resolvedContentSize(
            preferred: preferredContentSize,
            fitting: hostingView.fittingSize,
            visibleSize: anchorVisibleFrame.size
        )
        preferredFrame = Self.centeredFrame(contentSize: resolvedContentSize, in: anchorVisibleFrame)
        setFrame(preferredFrame, display: false)
    }

    /// Converts a content-area size into a full window frame (titlebar chrome
    /// included) centered inside `visibleFrame`, so what ends up mid-screen is
    /// the window the user sees rather than just its content rect.
    private static func centeredFrame(contentSize: CGSize, in visibleFrame: NSRect) -> NSRect {
        let frameSize = frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: style
        ).size
        return AnnotationEditorWindowGeometry.centeredFrame(size: frameSize, in: visibleFrame)
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
        // Re-apply the centered frame on first presentation only. Some AppKit
        // path repositions titled panels between init and ordering front, which
        // left the Annotate window off-center (issue #236). Doing this on every
        // `show()` would yank a window the user has since moved back to center.
        if !hasAppliedPreferredFrame {
            hasAppliedPreferredFrame = true
            setFrame(preferredFrame, display: false)
        }
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
