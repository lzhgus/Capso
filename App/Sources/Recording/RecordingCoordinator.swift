// App/Sources/Recording/RecordingCoordinator.swift
import AppKit
import Observation
import HistoryKit
import RecordingKit
import CameraKit
import CaptureKit
import SharedKit
import ExportKit
import EffectsKit

/// Orchestrates recording flow:
/// 1. Show overlay for area selection (drag or Space for window)
/// 2. Show recording toolbar (format, camera, mic, audio)
/// 3. User clicks Record → start recording with selected area
/// 4. Show controls (pause/stop/timer) + red border
/// 5. Stop → finalize MP4
@MainActor
@Observable
final class RecordingCoordinator {
    private let settings: AppSettings
    let recorder = ScreenRecorder()
    let cameraManager = CameraManager()
    var historyCoordinator: HistoryCoordinator?

    private var overlayWindows: [CaptureOverlayWindow] = []
    private var toolbarWindow: RecordingToolbarWindow?
    private var selectionBorderWindow: SelectionBorderWindow?
    private var controlsWindow: RecordingControlsWindow?
    private var borderWindow: RecordingBorderWindow?
    private var cameraPiPWindow: CameraPiPWindow?
    private var recordingPreviewWindow: RecordingPreviewWindow?
    private var clickMonitor: ClickMonitor?
    private var clickHighlightWindow: ClickHighlightWindow?
    private var countdownWindow: CountdownWindow?
    private var escGlobalMonitor: Any?
    private var escLocalMonitor: Any?
    private var escEventTap: CFMachPort?
    private var escEventTapRunLoopSource: CFRunLoopSource?

    // Selection state
    private var selectedRect: CGRect = .zero
    private var selectedScreen: NSScreen?
    private var selectedDisplayID: CGDirectDisplayID = CGMainDisplayID()

    // Current recording inputs (used by restart)
    private var currentRecordingFormat: RecordingFormatChoice?
    private var currentCameraEnabled = false
    private var currentMicEnabled = false
    private var currentSystemAudioEnabled = false

    init(settings: AppSettings) {
        self.settings = settings
        cameraManager.refreshDevices()
    }

    // MARK: - Public API

    /// Start the recording flow: show overlay for area selection.
    func startRecordingFlow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.showAreaSelectionOverlay()
        }
    }

    // MARK: - Step 1: Area Selection

    private func showAreaSelectionOverlay() {
        dismissOverlay()

        for screen in NSScreen.screens {
            let overlay = CaptureOverlayWindow(screen: screen, settings: settings, presetsDisabled: true)
            overlay.onAreaSelected = { [weak self] rect, screen in
                self?.dismissOverlay()
                self?.handleAreaSelected(rect: rect, screen: screen)
            }
            overlay.onWindowSelected = { [weak self] windowID in
                self?.dismissOverlay()
                self?.handleWindowSelected(windowID: windowID)
            }
            overlay.onCancelled = { [weak self] in
                self?.dismissOverlay()
            }
            // Use area mode — user can drag to select recording region
            overlay.activate(mode: .area)
            overlayWindows.append(overlay)
        }
    }

    private func handleAreaSelected(rect: CGRect, screen: NSScreen) {
        selectedScreen = screen
        selectedDisplayID = screen.displayID

        // `rect` comes from the overlay view in view-local coordinates:
        // (0,0) at the screen's bottom-left, width/height = screen dimensions.
        // Convert to the display-local top-down coord system that every
        // downstream consumer expects (ScreenCaptureKit, CountdownWindow,
        // showRecordingControls, showBorder — all of them do `+ origin` to
        // turn this back into global AppKit coords).
        //
        // Previously this code subtracted `screenFrame.origin.x` from a
        // view-local X, which mixed coordinate systems and happened to work
        // only for the primary screen (whose origin is (0,0)). On a
        // secondary display, the resulting rect ended up on the primary
        // screen after downstream conversion, so the recording border and
        // controls toolbar both landed on the wrong display.
        let screenFrame = screen.frame
        let flippedY = screenFrame.height - rect.maxY
        selectedRect = CGRect(
            x: rect.origin.x,
            y: flippedY,
            width: rect.width,
            height: rect.height
        )

        // Show the recording toolbar below the selected area
        showToolbar(selectionViewRect: rect, screen: screen)
    }

    private func handleWindowSelected(windowID: CGWindowID) {
        // If window selection happens, get window frame and use that
        Task {
            let windows = try? await ContentEnumerator.windows()
            guard let window = windows?.first(where: { $0.id == windowID }) else { return }

            let screen = NSScreen.main ?? NSScreen.screens.first!
            selectedScreen = screen
            selectedDisplayID = screen.displayID
            selectedRect = window.frame

            // Convert screen rect to view rect for toolbar positioning
            let screenFrame = screen.frame
            let viewY = screenFrame.height - window.frame.origin.y - window.frame.height
            let viewRect = CGRect(
                x: window.frame.origin.x,
                y: viewY,
                width: window.frame.width,
                height: window.frame.height
            )
            showToolbar(selectionViewRect: viewRect, screen: screen)
        }
    }

    // MARK: - Step 2: Recording Toolbar

    private func showToolbar(selectionViewRect: CGRect, screen: NSScreen) {
        // `selectionViewRect` is view-local (0-based, bottom-left origin on
        // the given screen). Both `SelectionBorderWindow` and
        // `RecordingToolbarWindow` position themselves in GLOBAL AppKit
        // screen coordinates, so convert before handing off. Without this,
        // everything lines up by accident only on the primary display.
        let globalSelectionRect = CGRect(
            x: selectionViewRect.origin.x + screen.frame.origin.x,
            y: selectionViewRect.origin.y + screen.frame.origin.y,
            width: selectionViewRect.width,
            height: selectionViewRect.height
        )

        // Show selection border with corner handles (persists while toolbar is visible)
        selectionBorderWindow = SelectionBorderWindow(selectionRect: globalSelectionRect, screen: screen)
        selectionBorderWindow?.show()

        toolbarWindow = RecordingToolbarWindow(
            selectionRect: globalSelectionRect,
            screen: screen,
            settings: settings,
            onRecord: { [weak self] format, cameraEnabled, cameraDeviceID, micEnabled, systemAudioEnabled in
                guard let self else { return }
                let willShowCountdown = self.settings.showCountdown && self.selectedScreen != nil
                self.dismissToolbarUI(keepCamera: cameraEnabled, removeEscapeMonitors: !willShowCountdown)
                if let cameraDeviceID {
                    self.cameraManager.selectedDeviceID = cameraDeviceID
                }
                self.startRecording(
                    format: format,
                    cameraEnabled: cameraEnabled,
                    micEnabled: micEnabled,
                    systemAudioEnabled: systemAudioEnabled
                )
            },
            onCameraToggled: { [weak self] enabled, deviceID in
                if enabled {
                    if let deviceID {
                        self?.cameraManager.selectedDeviceID = deviceID
                    }
                    self?.cameraManager.stop()
                    try? self?.cameraManager.start()
                    self?.showCameraPiP()
                } else {
                    self?.cameraPiPWindow?.close()
                    self?.cameraPiPWindow = nil
                    self?.cameraManager.stop()
                }
            },
            onCancel: { [weak self] in
                self?.cancelPendingRecordingFlow()
            },
            onCameraSettingsChanged: { [weak self] in
                self?.cameraPiPWindow?.applySettings()
            }
        )
        toolbarWindow?.show()

        installEscapeMonitors()
    }

    private func installEscapeMonitors() {
        removeEscapeMonitors()

        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                Task { @MainActor in
                    self?.cancelPendingRecordingFlow()
                }
            }
        }
        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    self?.cancelPendingRecordingFlow()
                }
                return nil
            }
            return event
        }

        installEscapeEventTap()
    }

    private func removeEscapeMonitors() {
        if let m = escGlobalMonitor { NSEvent.removeMonitor(m); escGlobalMonitor = nil }
        if let m = escLocalMonitor { NSEvent.removeMonitor(m); escLocalMonitor = nil }
        if let source = escEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            escEventTapRunLoopSource = nil
        }
        if let tap = escEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            escEventTap = nil
        }
    }

    private func installEscapeEventTap() {
        // Keep ESC working even if focus moves away from the setup toolbar.
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                guard type == .keyDown,
                      event.getIntegerValueField(.keyboardEventKeycode) == 53,
                      let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let coordinator = Unmanaged<RecordingCoordinator>.fromOpaque(refcon).takeUnretainedValue()
                Task { @MainActor in
                    coordinator.cancelPendingRecordingFlow()
                }
                return nil
            },
            userInfo: refcon
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        escEventTap = tap
        escEventTapRunLoopSource = source
    }

    private func cancelPendingRecordingFlow() {
        if cameraPiPWindow?.presentationModeActive == true {
            cameraPiPWindow?.exitPresentationMode()
            return
        }

        countdownWindow?.cancel()
        countdownWindow = nil
        dismissToolbarUI()
    }

    private func dismissToolbarUI(keepCamera: Bool = false, removeEscapeMonitors shouldRemoveEscapeMonitors: Bool = true) {
        toolbarWindow?.close()
        toolbarWindow = nil
        selectionBorderWindow?.close()
        selectionBorderWindow = nil
        if !keepCamera {
            cameraPiPWindow?.close()
            cameraPiPWindow = nil
            cameraManager.stop()
        }
        if shouldRemoveEscapeMonitors {
            removeEscapeMonitors()
        }
    }

    // MARK: - Step 3: Start Recording

    private func startRecording(
        format: RecordingFormatChoice,
        cameraEnabled: Bool,
        micEnabled: Bool,
        systemAudioEnabled: Bool
    ) {
        currentRecordingFormat = format
        currentCameraEnabled = cameraEnabled
        currentMicEnabled = micEnabled
        currentSystemAudioEnabled = systemAudioEnabled

        let config = RecordingConfig(
            captureRect: selectedRect,
            displayID: selectedDisplayID,
            format: format == .gif ? .gif : .video,
            fps: 30,
            captureSystemAudio: systemAudioEnabled,
            captureMicrophone: micEnabled,
            showCursor: settings.showCursor
        )

        // Start camera if not already running from toolbar preview.
        // Permission was already requested in onCameraToggled, so this
        // uses the sync `start()` — at this point we know it's granted.
        if cameraEnabled && cameraPiPWindow == nil {
            try? cameraManager.start()
            showCameraPiP()
        }

        let actuallyStart: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                do {
                    // Show the red border before starting the stream so its
                    // window ID can be passed to SCContentFilter — otherwise
                    // it gets composited into the first captured frames.
                    self.showBorder()
                    self.borderWindow?.displayIfNeeded()
                    let excludeIDs: [CGWindowID]
                    if let n = self.borderWindow?.windowNumber, n > 0 {
                        excludeIDs = [CGWindowID(n)]
                    } else {
                        excludeIDs = []
                    }
                    try await self.recorder.startRecording(config: config, excludeWindowIDs: excludeIDs)
                    self.startClickHighlight()
                    self.showRecordingControls()
                } catch {
                    print("Recording failed to start: \(error)")
                    self.borderWindow?.hide()
                    self.borderWindow = nil
                    if cameraEnabled {
                        self.cameraPiPWindow?.close()
                        self.cameraPiPWindow = nil
                        self.cameraManager.stop()
                    }
                }
            }
        }

        if settings.showCountdown, let screen = selectedScreen {
            let cd = CountdownWindow(selectionRect: selectedRect, screen: screen)
            countdownWindow = cd
            cd.runCountdown {
                self.countdownWindow = nil
                self.removeEscapeMonitors()
                actuallyStart()
            }
        } else {
            actuallyStart()
        }
    }

    // MARK: - Step 4: During Recording

    func stopRecording() {
        Task {
            do {
                let result = try await recorder.stopRecording()
                hideRecordingUI()

                let tempURL = result.fileURL

                // Save to history immediately (before user decides to Save/discard)
                let format = result.format as RecordingKit.RecordingFormat
                saveRecordingToHistory(url: tempURL, format: format)

                // Extract thumbnail and show preview
                let thumbnail = await VideoThumbnail.extractThumbnail(from: tempURL)
                let nsThumb = thumbnail.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
                let size = VideoThumbnail.formattedFileSize(VideoThumbnail.fileSize(at: tempURL))
                let duration = VideoThumbnail.formattedDuration(result.duration)

                showRecordingPreview(thumbnail: nsThumb, duration: duration, fileSize: size,
                                    tempURL: tempURL, format: result.format as RecordingKit.RecordingFormat)
            } catch {
                print("Failed to stop/save recording: \(error)")
                hideRecordingUI()
            }
        }
    }

    private func restartRecording() {
        guard let format = currentRecordingFormat else { return }

        Task {
            do {
                let result = try await recorder.stopRecording()
                // Discard temp file — restart should not show preview.
                try? FileManager.default.removeItem(at: result.fileURL)
                hideRecordingUI()

                startRecording(
                    format: format,
                    cameraEnabled: currentCameraEnabled,
                    micEnabled: currentMicEnabled,
                    systemAudioEnabled: currentSystemAudioEnabled
                )
            } catch {
                print("Failed to restart recording: \(error)")
                hideRecordingUI()
            }
        }
    }

    private func confirmDeleteRecording() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Delete this recording?")
        alert.informativeText = String(localized: "The current recording will be permanently discarded.")
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        Task {
            do {
                let result = try await recorder.stopRecording()
                try? FileManager.default.removeItem(at: result.fileURL)
                hideRecordingUI()
            } catch {
                print("Failed to delete recording: \(error)")
                hideRecordingUI()
            }
        }
    }

    private func exportRecording(
        _ tempURL: URL,
        format: RecordingKit.RecordingFormat,
        destinationOverride: URL? = nil,
        deleteSourceOnSuccess: Bool = true,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> URL? {
        let exportFormat: ExportFormat = format == .gif ? .gif : .mp4
        let fileFormat: FileFormat = format == .gif ? .gif : .mp4
        let destURL: URL
        if let destinationOverride {
            destURL = destinationOverride
        } else {
            let exportDir = settings.exportLocation
            let fileName = FileNaming.generateFileName(for: .recording, format: fileFormat)
            destURL = exportDir.appendingPathComponent(fileName)
        }
        let exportDir = destURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let options = ExportOptions(
            format: exportFormat,
            quality: settings.exportQuality,
            destination: destURL
        )

        do {
            let result = try await VideoExporter.export(source: tempURL, options: options, progress: progress)
            if deleteSourceOnSuccess {
                // Clean up temp file after successful export
                try? FileManager.default.removeItem(at: tempURL)
            }
            return result
        } catch {
            // Use NSLog so the error is visible in Console.app — `print` only
            // surfaces under Xcode-attached debugging.
            NSLog("[Capso] Recording export FAILED (format=%@, dest=%@): %@",
                  String(describing: format), destURL.path,
                  String(describing: error))
            return nil
        }
    }

    private func showRecordingSaveFailureAlert(format: RecordingKit.RecordingFormat) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn't save recording")
        let kind = format == .gif ? String(localized: "GIF") : String(localized: "video")
        alert.informativeText = String(localized: "Saving the \(kind) to \(settings.exportLocation.path) failed. The recording is still available in the preview — close this dialog and try Save again, or use Copy.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    private func showRecordingCopyFailureAlert(format: RecordingKit.RecordingFormat) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn't copy recording")
        let kind = format == .gif ? String(localized: "GIF") : String(localized: "video")
        alert.informativeText = String(localized: "Copying the \(kind) to the clipboard failed. The recording is still available in the preview — close this dialog and try Copy again, or use Save.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    private func showRecordingPreview(thumbnail: NSImage?, duration: String, fileSize: String,
                                      tempURL: URL, format: RecordingKit.RecordingFormat) {
        recordingPreviewWindow?.close()
        recordingPreviewWindow = nil

        let state = RecordingPreviewState()
        let window = RecordingPreviewWindow(
            thumbnail: thumbnail, duration: duration, fileSize: fileSize,
            state: state, settings: settings
        )

        window.onCopy = { [weak self, weak window] in
            // Ignore Copy if a save is already running — same reason we
            // disable the buttons in the view (avoid double-write races).
            guard !state.isSaving else { return }
            guard let self else { return }
            state.isSaving = true
            state.saveProgress = 0
            state.progressLabel = String(localized: "Copying…")
            window?.cancelAutoDismissForSave()

            Task { @MainActor in
                let clipboardURL = await self.exportRecordingToClipboard(tempURL, format: format) { progress in
                    Task { @MainActor in
                        state.saveProgress = progress
                    }
                }

                if let clipboardURL {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([clipboardURL as NSURL])
                    self.recordingPreviewWindow?.close()
                    self.recordingPreviewWindow = nil
                } else {
                    state.isSaving = false
                    state.saveProgress = 0
                    state.progressLabel = String(localized: "Saving…")
                    self.showRecordingCopyFailureAlert(format: format)
                }
            }
        }

        window.onSave = { [weak self, weak window] in
            guard let self else { return }
            // Ignore further clicks while a save is in flight — without
            // this guard, repeated clicks during a slow GIF export would
            // queue up multiple identical saves and write duplicate files.
            guard !state.isSaving else { return }
            state.isSaving = true
            state.saveProgress = 0
            state.progressLabel = String(localized: "Saving…")
            window?.cancelAutoDismissForSave()

            Task { @MainActor in
                let result = await self.exportRecording(tempURL, format: format) { progress in
                    // VideoExporter calls this from background contexts;
                    // hop to MainActor to mutate Observable state safely.
                    Task { @MainActor in
                        state.saveProgress = progress
                    }
                }

                if result != nil {
                    self.recordingPreviewWindow?.close()
                    self.recordingPreviewWindow = nil
                } else {
                    // Reset state so the buttons return and the user can
                    // retry without restarting the recording.
                    state.isSaving = false
                    state.saveProgress = 0
                    self.showRecordingSaveFailureAlert(format: format)
                }
            }
        }

        window.onClose = { [weak self] in
            // Closing mid-export would orphan the temp file with no UI to
            // recover from. Block until the save finishes.
            guard !state.isSaving else { return }
            self?.recordingPreviewWindow?.close()
            self?.recordingPreviewWindow = nil
        }

        window.show()
        recordingPreviewWindow = window
    }

    private func exportRecordingToClipboard(
        _ tempURL: URL,
        format: RecordingKit.RecordingFormat,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> URL? {
        let fileFormat: FileFormat = format == .gif ? .gif : .mp4
        let clipboardDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-clipboard-exports", isDirectory: true)
        let destinationURL = clipboardDir
            .appendingPathComponent("capso_clipboard_\(UUID().uuidString).\(FileNaming.fileExtension(for: fileFormat))")

        return await exportRecording(
            tempURL,
            format: format,
            destinationOverride: destinationURL,
            progress: progress
        )
    }

    // MARK: - UI Helpers

    private func dismissOverlay() {
        for window in overlayWindows {
            window.deactivate()
        }
        overlayWindows.removeAll()
    }

    private func startClickHighlight() {
        guard settings.highlightClicks else { return }

        let window = ClickHighlightWindow(displayID: selectedDisplayID)
        window.showWindow()
        clickHighlightWindow = window

        let monitor = ClickMonitor()
        monitor.onClick = { [weak self] point in
            Task { @MainActor in
                self?.clickHighlightWindow?.showClick(at: point)
            }
        }
        monitor.start()
        clickMonitor = monitor
    }

    private func stopClickHighlight() {
        clickMonitor?.stop()
        clickMonitor = nil
        clickHighlightWindow?.hideWindow()
        clickHighlightWindow?.close()
        clickHighlightWindow = nil
    }

    private func showRecordingControls() {
        guard let screen = selectedScreen else { return }

        let screenFrame = screen.frame
        let viewY = screenFrame.height - selectedRect.origin.y - selectedRect.height
        let recordingFrame = CGRect(
            x: selectedRect.origin.x + screenFrame.origin.x,
            y: viewY + screenFrame.origin.y,
            width: selectedRect.width,
            height: selectedRect.height
        )

        controlsWindow = RecordingControlsWindow(
            recordingFrame: recordingFrame,
            screen: screen,
            recorder: recorder,
            onStop: { [weak self] in self?.stopRecording() },
            onRestart: { [weak self] in self?.restartRecording() },
            onDelete: { [weak self] in self?.confirmDeleteRecording() }
        )
        controlsWindow?.show()
    }

    private func showBorder() {
        guard let screen = selectedScreen else { return }
        // Convert selectedRect (display-local top-down) back to global AppKit
        // coordinates for the border window's frame.
        let screenFrame = screen.frame
        let viewY = screenFrame.height - selectedRect.origin.y - selectedRect.height
        let borderFrame = CGRect(
            x: selectedRect.origin.x + screenFrame.origin.x,
            y: viewY + screenFrame.origin.y,
            width: selectedRect.width,
            height: selectedRect.height
        )
        borderWindow = RecordingBorderWindow(frame: borderFrame, screen: screen)
        borderWindow?.show()
    }

    private func showCameraPiP() {
        // Close existing PiP first to prevent duplicates
        cameraPiPWindow?.orderOut(nil)
        cameraPiPWindow?.close()
        cameraPiPWindow = nil

        var recordingFrame: CGRect?
        if let screen = selectedScreen {
            let screenFrame = screen.frame
            let viewY = screenFrame.height - selectedRect.origin.y - selectedRect.height
            recordingFrame = CGRect(
                x: selectedRect.origin.x + screenFrame.origin.x,
                y: viewY + screenFrame.origin.y,
                width: selectedRect.width,
                height: selectedRect.height
            )
        }
        cameraPiPWindow = CameraPiPWindow(cameraManager: cameraManager, settings: settings, recordingFrame: recordingFrame)
        cameraPiPWindow?.show()
    }

    private func hideRecordingUI() {
        stopClickHighlight()
        controlsWindow?.close()
        controlsWindow = nil
        borderWindow?.hide()
        borderWindow = nil
        // Force PiP window off screen before closing
        cameraPiPWindow?.orderOut(nil)
        cameraPiPWindow?.close()
        cameraPiPWindow = nil
        cameraManager.stop()
    }

    private func saveRecordingToHistory(url: URL, format: RecordingKit.RecordingFormat) {
        guard let historyCoordinator else { return }
        let mode: HistoryCaptureMode = format == .gif ? .gif : .recording
        historyCoordinator.saveRecording(url: url, mode: mode)
    }
}
