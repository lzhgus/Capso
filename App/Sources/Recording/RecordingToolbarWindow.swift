// App/Sources/Recording/RecordingToolbarWindow.swift
import AppKit
import Observation
import SwiftUI
import SharedKit

@Observable
@MainActor
private final class RecordingToolbarState {
    var cameraEnabled = false
    var selectedCameraID: String?
    var micEnabled = false
    var systemAudioEnabled = true
}

/// Floating toolbar shown after area selection, before recording starts.
@MainActor
final class RecordingToolbarWindow: NSPanel {
    private let settings: AppSettings
    private let onCancelAction: () -> Void
    private let onRecordAction: (RecordingFormatChoice, Bool, String?, Bool, Bool) -> Void
    private let toolbarState = RecordingToolbarState()

    init(
        selectionRect: CGRect,
        screen: NSScreen,
        settings: AppSettings,
        onRecord: @escaping (RecordingFormatChoice, Bool, String?, Bool, Bool) -> Void,
        onCameraToggled: @escaping (Bool, String?) async -> Bool,
        onChangeArea: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onCameraSettingsChanged: @escaping () -> Void
    ) {
        self.settings = settings
        self.onCancelAction = onCancel
        self.onRecordAction = onRecord
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

        let outputSize = Self.outputVideoSize(for: selectionRect, screen: screen)
        let view = RecordingToolbarWrapper(
            width: outputSize.width,
            height: outputSize.height,
            settings: settings,
            state: toolbarState,
            onRecord: onRecord,
            onCameraToggled: onCameraToggled,
            onChangeArea: onChangeArea,
            onCancel: onCancel,
            onCameraSettingsChanged: onCameraSettingsChanged
        )
        self.contentView = NSHostingView(rootView: view)
    }

    private static func outputVideoSize(for selectionRect: CGRect, screen: NSScreen) -> (width: Int, height: Int) {
        let scale = max(screen.backingScaleFactor, 1)
        return (
            width: ensureEven(max(1, Int(ceil(selectionRect.width * scale)))),
            height: ensureEven(max(1, Int(ceil(selectionRect.height * scale))))
        )
    }

    private static func ensureEven(_ value: Int) -> Int {
        value % 2 == 0 ? value : value + 1
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
        if event.keyCode == 36 { // Return
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.isEmpty || modifiers == .option else {
                super.keyDown(with: event)
                return
            }
            onRecordAction(
                modifiers == .option ? .gif : .video,
                toolbarState.cameraEnabled,
                toolbarState.selectedCameraID,
                toolbarState.micEnabled,
                toolbarState.systemAudioEnabled
            )
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
    @Bindable var state: RecordingToolbarState
    let onRecord: (RecordingFormatChoice, Bool, String?, Bool, Bool) -> Void
    let onCameraToggled: (Bool, String?) async -> Bool
    let onChangeArea: () -> Void
    let onCancel: () -> Void
    let onCameraSettingsChanged: () -> Void

    @State private var cameraToggleTask: Task<Void, Never>?

    var body: some View {
        RecordingToolbarView(
            width: width,
            height: height,
            cameraEnabled: $state.cameraEnabled,
            selectedCameraID: $state.selectedCameraID,
            micEnabled: $state.micEnabled,
            systemAudioEnabled: $state.systemAudioEnabled,
            settings: settings,
            onRecordVideo: {
                onRecord(
                    .video,
                    state.cameraEnabled,
                    state.selectedCameraID,
                    state.micEnabled,
                    state.systemAudioEnabled
                )
            },
            onRecordGIF: {
                onRecord(
                    .gif,
                    state.cameraEnabled,
                    state.selectedCameraID,
                    state.micEnabled,
                    state.systemAudioEnabled
                )
            },
            onChangeArea: onChangeArea,
            onCancel: onCancel,
            onCameraSettingsChanged: onCameraSettingsChanged
        )
        .onChange(of: state.cameraEnabled) { _, newValue in
            updateCamera(enabled: newValue, deviceID: state.selectedCameraID)
        }
        .onChange(of: state.selectedCameraID) { _, newValue in
            if state.cameraEnabled {
                updateCamera(enabled: true, deviceID: newValue)
            }
        }
        .onDisappear {
            cameraToggleTask?.cancel()
        }
    }

    private func updateCamera(enabled: Bool, deviceID: String?) {
        cameraToggleTask?.cancel()
        cameraToggleTask = Task { @MainActor in
            let didApply = await onCameraToggled(enabled, deviceID)
            guard !Task.isCancelled else { return }
            if enabled && !didApply {
                state.cameraEnabled = false
                state.selectedCameraID = nil
            }
        }
    }
}
