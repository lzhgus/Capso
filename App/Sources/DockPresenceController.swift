import AppKit

/// Shows Capso in the Dock and the Cmd+Tab switcher while an editor-style
/// window (Annotate, Screenshot History, Settings, the recording editor) is
/// open, and returns to a menu-bar-only app once the last one closes.
///
/// Windows opt in by setting `identifier` to `windowIdentifier`, so auxiliary
/// panels such as the color picker, OCR overlay, or Quick Access never count.
@MainActor
final class DockPresenceController {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("com.capso.dockPresence")

    private var observers: [NSObjectProtocol] = []
    private var updateScheduled = false

    init() {
        let windowNotifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.willCloseNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]
        for name in windowNotifications + [NSApplication.didUnhideNotification] {
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

    /// Miniaturized windows still count: their Dock tile is the only way back.
    static func shouldShowInDock(windows: [NSWindow]) -> Bool {
        windows.contains { window in
            window.identifier == windowIdentifier
                && (window.isVisible || window.isMiniaturized)
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

    static func policy(
        windows: [NSWindow],
        appIsHidden: Bool,
        current: NSApplication.ActivationPolicy
    ) -> NSApplication.ActivationPolicy {
        // Hiding the app orders every window out; keep the Dock tile so the
        // user can bring the hidden editor back.
        if appIsHidden { return current }
        return shouldShowInDock(windows: windows) ? .regular : .accessory
    }

    private func applyPolicy() {
        let current = NSApp.activationPolicy()
        let policy = Self.policy(windows: NSApp.windows, appIsHidden: NSApp.isHidden, current: current)
        guard current != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Switching to `.regular` does not always bring the app forward.
        if policy == .regular {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
