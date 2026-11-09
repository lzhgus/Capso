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
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleUpdate()
            }
        })
    }

    /// Where the tagged windows sit relative to the Space the user is on.
    enum ActiveSpace {
        case normal
        /// Another app's full-screen Space. Menus of a `.regular` app open
        /// off screen there, so pop-up buttons look dead.
        case otherAppFullScreen
        /// No tagged window is on the active Space.
        case elsewhere
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
        current: NSApplication.ActivationPolicy,
        activeSpace: ActiveSpace = .normal
    ) -> NSApplication.ActivationPolicy {
        // Hiding the app orders every window out; keep the Dock tile so the
        // user can bring the hidden editor back.
        if appIsHidden { return current }
        guard shouldShowInDock(windows: windows) else { return .accessory }
        switch activeSpace {
        case .normal: return .regular
        case .otherAppFullScreen: return .accessory
        // Activating as `.regular` from another Space would pull the user
        // back to the editor's Space.
        case .elsewhere: return current
        }
    }

    static func activeSpace(of windows: [NSWindow]) -> ActiveSpace {
        let tagged = windows.filter { $0.identifier == windowIdentifier }
        if tagged.contains(where: \.isMiniaturized) { return .normal }
        guard let screen = tagged.first(where: { $0.isVisible && $0.isOnActiveSpace })?.screen else {
            return .elsewhere
        }
        return isOtherAppFullScreen(on: screen) ? .otherAppFullScreen : .normal
    }

    /// ponytail: a full-screen Space shows exactly one window covering the
    /// whole display, menu bar strip included; a desktop window rarely does.
    /// A false positive only hides the Dock tile. Swap in a Space-type API if
    /// AppKit ever ships one.
    private static func isOtherAppFullScreen(on screen: NSScreen) -> Bool {
        let display = CGDisplayBounds(screen.displayID)
        let pid = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != pid,
                  let boundsInfo = info[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as! CFDictionary) else { return false }
            return bounds.contains(display)
        }
    }

    private func applyPolicy() {
        let current = NSApp.activationPolicy()
        let policy = Self.policy(
            windows: NSApp.windows,
            appIsHidden: NSApp.isHidden,
            current: current,
            activeSpace: Self.activeSpace(of: NSApp.windows)
        )
        guard current != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Switching to `.regular` does not always bring the app forward.
        if policy == .regular {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
