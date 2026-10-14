// App/Sources/History/HistoryWindow.swift
import AppKit
import Quartz
import SwiftUI

@MainActor
final class HistoryWindow {
    private var window: NSWindow?
    private let coordinator: HistoryCoordinator

    init(coordinator: HistoryCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        if let window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = HistoryNSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Screenshot History")
        window.minSize = NSSize(width: 480, height: 400)
        window.isReleasedWhenClosed = false
        window.center()

        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .sidebar
        visualEffect.state = .active
        window.contentView = visualEffect

        let hostingView = NSHostingView(rootView: HistoryView(coordinator: coordinator) { [weak window] urls in
            window?.toggleQuickLook(for: urls)
        })
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

    func toggle() {
        guard let window else {
            show()
            return
        }

        if window.isVisible, !window.isMiniaturized {
            window.orderOut(nil)
        } else {
            show()
        }
    }

#if DEBUG
    var isVisibleForTesting: Bool {
        window?.isVisible == true && window?.isMiniaturized == false
    }
#endif
}

/// Hosts Quick Look for the history grid: Space previews the selected captures.
private final class HistoryNSWindow: NSWindow, QLPreviewPanelDataSource {
    private var previewURLs: [URL] = []

    func toggleQuickLook(for urls: [URL]) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
            return
        }
        guard !urls.isEmpty else { return }
        previewURLs = urls
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        // Older SDKs don't mark these callbacks main-actor, though AppKit calls them there.
        MainActor.assumeIsolated { panel.dataSource = self }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { panel.dataSource = nil }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { previewURLs.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { previewURLs[index] as NSURL }
    }
}
