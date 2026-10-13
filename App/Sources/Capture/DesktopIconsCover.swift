import AppKit
@preconcurrency import ScreenCaptureKit

/// Hides desktop icons by covering them with each screen's wallpaper. The cover
/// sits just above the icon layer and below every app window, ignores the mouse,
/// and shows up in screenshots and recordings like the real desktop would.
@MainActor
final class DesktopIconsCover {
    /// Turned on from the menu bar or an automation URL.
    private(set) var isHiddenManually = false
    /// Turned on for the length of a recording.
    private var isHiddenForRecording = false
    private var windows: [NSWindow] = []
    private var observers: [NSObjectProtocol] = []

    var areIconsHidden: Bool { isHiddenManually || isHiddenForRecording }

    func setHiddenManually(_ hidden: Bool) {
        isHiddenManually = hidden
        update()
    }

    func setHiddenForRecording(_ hidden: Bool) {
        isHiddenForRecording = hidden
        update()
    }

    private func update() {
        if areIconsHidden {
            if windows.isEmpty { show() }
        } else {
            hide()
        }
    }

    private func show() {
        rebuildWindows()
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildWindows() }
            },
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildWindows() }
            },
        ]
    }

    private func hide() {
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            NotificationCenter.default.removeObserver($0)
        }
        observers = []
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        let screens = NSScreen.screens
        windows = screens.map(makeWindow(for:))
        windows.forEach { $0.orderFrontRegardless() }

        let current = windows
        Task { [weak self] in
            let images = await Self.wallpaperImages(for: screens)
            guard let self, self.windows == current else { return }
            for (window, image) in zip(current, images) {
                if let image {
                    window.contentView?.layer?.contents = image
                    window.contentView?.layer?.contentsGravity = .resizeAspectFill
                }
                window.alphaValue = 1
            }
        }
    }

    /// Captures the system's own wallpaper window for each screen, which works
    /// for every kind of wallpaper (photos, dynamic, colours, shuffles).
    private static func wallpaperImages(for screens: [NSScreen]) async -> [CGImage?] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return screens.map { _ in nil }
        }
        // The wallpaper window belongs to the Dock (WindowManager on newer macOS)
        // and sits at or just below the desktop window level.
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let owners: Set<String> = ["com.apple.dock", "com.apple.WindowManager"]
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var images: [CGImage?] = []
        for screen in screens {
            let f = screen.frame
            let globalFrame = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
            guard let window = content.windows.first(where: {
                $0.windowLayer <= desktopLevel && $0.frame == globalFrame
                    && owners.contains($0.owningApplication?.bundleIdentifier ?? "")
            }) else {
                images.append(nil)
                continue
            }
            let config = SCStreamConfiguration()
            config.width = Int(f.width * screen.backingScaleFactor)
            config.height = Int(f.height * screen.backingScaleFactor)
            config.showsCursor = false
            images.append(try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: config
            ))
        }
        return images
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1)
        // Stays invisible until the wallpaper has been captured, to avoid a flash.
        window.alphaValue = 0

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        return window
    }
}
