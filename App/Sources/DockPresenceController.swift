// App/Sources/DockPresenceController.swift
import AppKit

/// Shows Capso in the Dock and the Cmd+Tab app switcher only while a
/// document-style window (Annotate, Screenshot History, Settings, the
/// recording editor, ...) is open, and reverts to a pure menu-bar utility
/// once the last one closes.
///
/// Capso ships as an `LSUIElement` app, so by default it never appears in
/// Cmd+Tab — even with the annotation editor open. Clicking another app and
/// pressing Cmd+Tab therefore offered no way back to the editor (issue #286).
///
/// The controller watches window notifications instead of requiring every
/// window class to opt in. A window counts as document-style when it is
/// titled and closable; overlays, HUDs, Quick Access, and pinned screenshots
/// are all borderless and are ignored.
@MainActor
final class DockPresenceController {
    /// Lives as long as the app; observers are never removed on purpose.
    private var observers: [NSObjectProtocol] = []
    private var updateScheduled = false

    init() {
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.willCloseNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleUpdate()
                }
            })
        }
    }

    /// Whether `windows` contains at least one open document-style window.
    /// Miniaturized windows still count: their Dock tile is the only way to
    /// bring them back, so the app has to stay in the Dock.
    static func shouldShowInDock(windows: [NSWindow]) -> Bool {
        windows.contains { window in
            (window.isVisible || window.isMiniaturized)
                && window.styleMask.contains(.titled)
                && window.styleMask.contains(.closable)
        }
    }

    /// Coalesce to the next run-loop turn: `willCloseNotification` fires
    /// while the window still reports `isVisible == true`.
    private func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.updateScheduled = false
                self.applyPolicy()
            }
        }
    }

    private func applyPolicy() {
        let policy: NSApplication.ActivationPolicy =
            Self.shouldShowInDock(windows: NSApp.windows) ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Switching to `.regular` on its own does not always make the app
        // frontmost; re-activate so the freshly shown window gets focus.
        if policy == .regular {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
