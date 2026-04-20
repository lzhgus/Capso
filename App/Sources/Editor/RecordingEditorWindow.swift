import AppKit
import SwiftUI

final class RecordingEditorWindow: NSPanel {

    private let coordinator: EditorCoordinator

    init(coordinator: EditorCoordinator) {
        self.coordinator = coordinator

        let contentRect = NSRect(x: 0, y: 0, width: 960, height: 640)
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        title = String(localized: "Recording Editor")
        minSize = NSSize(width: 800, height: 540)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        titlebarAppearsTransparent = false

        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .sidebar
        visualEffect.state = .active
        contentView = visualEffect

        let editorView = RecordingEditorView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: editorView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])
    }

    func showCentered() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
