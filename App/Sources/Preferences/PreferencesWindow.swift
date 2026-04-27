// App/Sources/Preferences/PreferencesWindow.swift
import AppKit
import SwiftUI
import SharedKit

@MainActor
final class PreferencesWindow {
    private var window: NSWindow?
    private let settings: AppSettings
    private let updateManager: UpdateManager?

    init(settings: AppSettings, updateManager: UpdateManager? = nil) {
        self.settings = settings
        self.updateManager = updateManager
    }

    func show(tab: PreferencesTab? = nil) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Navigate to requested tab if window already exists.
            // Use a dedicated notification name (NOT .openScreenshotSettings)
            // to avoid recursing back through AppDelegate's observer.
            if let tab {
                NotificationCenter.default.post(name: .preferencesSwitchTab, object: tab)
            }
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Capso Settings")
        window.minSize = NSSize(width: 680, height: 480)
        window.maxSize = NSSize(width: 680, height: 480)
        window.isReleasedWhenClosed = false
        window.center()

        // Liquid Glass-inspired background
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .sidebar
        visualEffect.state = .active
        window.contentView = visualEffect

        let viewModel = PreferencesViewModel(settings: settings)
        let hostingView = NSHostingView(rootView: PreferencesView(viewModel: viewModel, updateManager: updateManager, initialTab: tab))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
