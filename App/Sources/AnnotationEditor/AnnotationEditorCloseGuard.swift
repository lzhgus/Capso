// App/Sources/AnnotationEditor/AnnotationEditorCloseGuard.swift
import AppKit

extension Notification.Name {
    /// Posted after the desktop (including any system alert) has been frozen.
    static let capsoCaptureDidFreezeDesktop = Notification.Name("capsoCaptureDidFreezeDesktop")
    /// Posted after the interactive capture overlay has been dismissed.
    static let capsoCaptureDidEnd = Notification.Name("capsoCaptureDidEnd")
}

@MainActor
enum AnnotationEditorCloseGuard {
    private static var suspendedAlertPresenter: AnnotationEditorSystemAlertPresenter?

    static func shouldClose(hasUnsavedChanges: Bool, confirmDiscard: () -> Bool) -> Bool {
        !hasUnsavedChanges || confirmDiscard()
    }

    static func presentDiscardAlert(above window: NSWindow?) -> Bool {
        let presenter = AnnotationEditorSystemAlertPresenter(above: window)
        switch presenter.runModal() {
        case .confirmed:
            return true
        case .cancelled:
            return false
        case .suspendedForCapture:
            suspendedAlertPresenter = presenter
            presenter.parkUntilCaptureEnds()
            return false
        }
    }

    fileprivate static func presenterDidFinish(_ presenter: AnnotationEditorSystemAlertPresenter) {
        if suspendedAlertPresenter === presenter {
            suspendedAlertPresenter = nil
        }
    }

#if DEBUG
    static var isSuspendedAlertVisibleForTesting: Bool {
        suspendedAlertPresenter?.isParkedAndVisible == true
    }

    static var isModelessAlertVisibleForTesting: Bool {
        suspendedAlertPresenter?.isModelessAndVisible == true
    }

    static func dismissSuspendedAlertForTesting() {
        suspendedAlertPresenter?.dismissWithoutResuming()
        suspendedAlertPresenter = nil
    }
#endif
}

/// Owns the original AppKit `NSAlert` while area capture temporarily suspends
/// its modal event loop. The same system window is restored after capture.
@MainActor
fileprivate final class AnnotationEditorSystemAlertPresenter: NSObject {
    enum Outcome {
        case confirmed
        case cancelled
        case suspendedForCapture
    }

    private let alert: NSAlert
    private weak var editorWindow: NSWindow?
    private let originalLevel: NSWindow.Level
    private var captureFreezeObserver: NSObjectProtocol?
    private var captureEndObserver: NSObjectProtocol?
    private var editorCloseObserver: NSObjectProtocol?
    private var isSuspendingForCapture = false
    private var isParked = false

    init(above window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Discard your edits?")
        alert.informativeText = String(localized: "Your annotations haven't been saved and will be lost.")
        alert.addButton(withTitle: String(localized: "Discard"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        // The inline area-capture editor's panel sits at `.screenSaver` level;
        // an unparented alert would render behind it, so lift the system alert
        // above whichever window is asking.
        if let window {
            alert.window.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        }

        self.alert = alert
        self.editorWindow = window
        self.originalLevel = alert.window.level
        super.init()
    }

    func runModal() -> Outcome {
        isSuspendingForCapture = false
        let observer = NotificationCenter.default.addObserver(
            forName: .capsoCaptureDidFreezeDesktop,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if NSApp.modalWindow === self.alert.window {
                    self.isSuspendingForCapture = true
                    NSApp.abortModal()
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let response = alert.runModal()
        if isSuspendingForCapture {
            return .suspendedForCapture
        }
        return response == .alertFirstButtonReturn ? .confirmed : .cancelled
    }

    func parkUntilCaptureEnds() {
        guard !isParked else { return }
        isParked = true

        // Keep the real NSAlert alive. The frozen desktop already contains its
        // pixels, so park it behind that layer and let the overlay receive all
        // pointer events until selection finishes.
        alert.window.ignoresMouseEvents = true
        alert.window.level = .screenSaver - 2
        alert.window.orderFrontRegardless()

        captureEndObserver = NotificationCenter.default.addObserver(
            forName: .capsoCaptureDidEnd,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resumeAfterCapture()
            }
        }
    }

#if DEBUG
    var isParkedAndVisible: Bool {
        isParked && alert.window.isVisible && alert.window.ignoresMouseEvents
    }

    var isModelessAndVisible: Bool {
        !isParked && alert.window.isVisible && NSApp.modalWindow !== alert.window
    }

    func dismissWithoutResuming() {
        finish()
    }
#endif

    private func resumeAfterCapture() {
        if let captureEndObserver {
            NotificationCenter.default.removeObserver(captureEndObserver)
            self.captureEndObserver = nil
        }

        isParked = false
        alert.window.ignoresMouseEvents = false
        alert.window.level = originalLevel
        installModelessButtonActions()
        installCaptureFreezeObserver()
        installEditorCloseObserver()
        alert.window.makeKeyAndOrderFront(nil)
    }

    private func installModelessButtonActions() {
        guard alert.buttons.count >= 2 else { return }

        alert.buttons[0].target = self
        alert.buttons[0].action = #selector(discardPressed)
        alert.buttons[0].keyEquivalent = "\r"

        alert.buttons[1].target = self
        alert.buttons[1].action = #selector(cancelPressed)
        alert.buttons[1].keyEquivalent = "\u{1b}"
    }

    private func installCaptureFreezeObserver() {
        guard captureFreezeObserver == nil else { return }
        captureFreezeObserver = NotificationCenter.default.addObserver(
            forName: .capsoCaptureDidFreezeDesktop,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.alert.window.isVisible else { return }
                self.parkUntilCaptureEnds()
            }
        }
    }

    private func installEditorCloseObserver() {
        guard editorCloseObserver == nil, let editorWindow else { return }
        editorCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: editorWindow,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.finish()
            }
        }
    }

    @objc private func discardPressed() {
        let window = editorWindow
        finish()
        window?.close()
    }

    @objc private func cancelPressed() {
        finish()
    }

    private func finish() {
        for observer in [captureFreezeObserver, captureEndObserver, editorCloseObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        captureFreezeObserver = nil
        captureEndObserver = nil
        editorCloseObserver = nil

        isParked = false
        alert.window.ignoresMouseEvents = false
        alert.window.orderOut(nil)
        AnnotationEditorCloseGuard.presenterDidFinish(self)
    }
}
