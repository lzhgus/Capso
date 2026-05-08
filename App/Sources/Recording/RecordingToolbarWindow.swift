// App/Sources/Recording/RecordingToolbarWindow.swift
import AppKit
import SwiftUI
import SharedKit

/// Floating toolbar shown after area selection, before recording starts.
@MainActor
final class RecordingToolbarWindow: NSPanel {
    private let settings: AppSettings
    private let onCancelAction: () -> Void

    init(
        selectionRect: CGRect,
        screen: NSScreen,
        settings: AppSettings,
        onRecord: @escaping (RecordingFormatChoice, Bool, String?, Bool, Bool) -> Void,
        onCameraToggled: @escaping (Bool, String?) -> Void,
        onChangeArea: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onCameraSettingsChanged: @escaping () -> Void
    ) {
        self.settings = settings
        self.onCancelAction = onCancel
        let width: CGFloat = 240
        let height: CGFloat = 220

        let screenFrame = screen.visibleFrame
        var x = selectionRect.midX - width / 2
        var y = selectionRect.midY - height / 2

        x = max(screenFrame.minX + 8, min(x, screenFrame.maxX - width - 8))
        y = max(screenFrame.minY + 8, min(y, screenFrame.maxY - height - 8))

        super.init(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver + 1
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.isMovableByWindowBackground = true

        let view = RecordingToolbarWrapper(
            width: Int(selectionRect.width),
            height: Int(selectionRect.height),
            settings: settings,
            onRecord: onRecord,
            onCameraToggled: onCameraToggled,
            onChangeArea: onChangeArea,
            onCancel: onCancel,
            onCameraSettingsChanged: onCameraSettingsChanged
        )
        self.contentView = NSHostingView(rootView: view)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(contentView)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onCancelAction()
            return
        }
        super.keyDown(with: event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct RecordingToolbarWrapper: View {
    let width: Int
    let height: Int
    let settings: AppSettings
    let onRecord: (RecordingFormatChoice, Bool, String?, Bool, Bool) -> Void
    let onCameraToggled: (Bool, String?) -> Void
    let onChangeArea: () -> Void
    let onCancel: () -> Void
    let onCameraSettingsChanged: () -> Void

    @State private var cameraEnabled = false
    @State private var selectedCameraID: String?
    @State private var micEnabled = false
    @State private var systemAudioEnabled = true

    var body: some View {
        RecordingToolbarView(
            width: width,
            height: height,
            cameraEnabled: $cameraEnabled,
            selectedCameraID: $selectedCameraID,
            micEnabled: $micEnabled,
            systemAudioEnabled: $systemAudioEnabled,
            settings: settings,
            onRecordVideo: {
                onRecord(.video, cameraEnabled, selectedCameraID, micEnabled, systemAudioEnabled)
            },
            onRecordGIF: {
                onRecord(.gif, cameraEnabled, selectedCameraID, micEnabled, systemAudioEnabled)
            },
            onChangeArea: onChangeArea,
            onCancel: onCancel,
            onCameraSettingsChanged: onCameraSettingsChanged
        )
        .onChange(of: cameraEnabled) { _, newValue in
            onCameraToggled(newValue, selectedCameraID)
        }
        .onChange(of: selectedCameraID) { _, newValue in
            if cameraEnabled {
                onCameraToggled(true, newValue)
            }
        }
    }
}
