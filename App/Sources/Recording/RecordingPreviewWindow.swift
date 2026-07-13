import AppKit
import SwiftUI
import SharedKit

@MainActor
final class RecordingPreviewWindow: NSPanel {
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?

    /// Reactive state for the in-place "Saving…" progress indicator. The
    /// coordinator mutates `state.isSaving` / `state.saveProgress` during
    /// export and the SwiftUI view re-renders automatically.
    let state: RecordingPreviewState

    private var autoDismissTimer: Timer?
    private let settings: AppSettings

    init(
        thumbnail: NSImage?,
        duration: String,
        fileSize: String,
        state: RecordingPreviewState,
        settings: AppSettings
    ) {
        self.state = state
        self.settings = settings

        let windowWidth: CGFloat = 340
        let windowHeight: CGFloat = 140

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let contentRect = QuickAccessStackGeometry.frame(
            position: settings.quickAccessPosition,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            windowSize: CGSize(width: windowWidth, height: windowHeight),
            stackIndex: 0,
            stackCount: 1
        )

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.isMovableByWindowBackground = true
        self.animationBehavior = .utilityWindow
        self.hidesOnDeactivate = false

        let view = RecordingPreviewView(
            thumbnail: thumbnail,
            duration: duration,
            fileSize: fileSize,
            state: state,
            onCopy: { [weak self] in self?.onCopy?() },
            onSave: { [weak self] in self?.onSave?() },
            onClose: { [weak self] in self?.onClose?() }
        )

        self.contentView = NSHostingView(rootView: view)
    }

    /// Cancel the auto-dismiss timer for the duration of an in-progress
    /// save. Without this, the timer might fire mid-export and silently
    /// pull the preview window out from under the user even though the
    /// save flow is still running.
    func cancelAutoDismissForSave() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
    }

    func show() {
        let finalFrame = frame
        var startFrame = finalFrame
        startFrame.origin.y -= 20
        setFrame(startFrame, display: false)
        alphaValue = 0

        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(finalFrame, display: true)
            self.animator().alphaValue = 1
        }

        if settings.quickAccessAutoClose {
            autoDismissTimer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval(settings.quickAccessAutoCloseInterval),
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.onClose?()
                }
            }
        }
    }

    override func close() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            super.close()
        })
    }
}
