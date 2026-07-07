// App/Sources/OCR/OCRCoordinator.swift
import AppKit
import Observation
import os.log
import CaptureKit
import OCRKit
import SharedKit

private let logger = Logger(subsystem: "com.awesomemacapps.capso", category: "OCR")

@MainActor
@Observable
final class OCRCoordinator {
    private let settings: AppSettings
    private var overlayWindows: [CaptureOverlayWindow] = []
    private var onboardingWindow: OCROnboardingWindow?
    private var ocrOverlayWindow: OCROverlayWindow?
    private var toastWindow: ToastWindow?

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Instant OCR

    func startInstantOCR() {
        if !settings.ocrOnboardingShown {
            showOnboarding { [weak self] in
                self?.beginInstantOCRFlow()
            }
        } else {
            beginInstantOCRFlow()
        }
    }

    private func beginInstantOCRFlow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.showOverlayForOCR()
        }
    }

    private func showOverlayForOCR() {
        dismissOverlay()
        for screen in NSScreen.screens {
            let overlay = CaptureOverlayWindow(screen: screen, settings: settings, presetsDisabled: true)
            overlay.onAreaSelected = { [weak self] rect, screen in
                self?.dismissOverlay()
                self?.performInstantOCR(rect: rect, screen: screen)
            }
            overlay.onCancelled = { [weak self] in
                self?.dismissOverlay()
            }
            overlay.activate(mode: .area)
            overlayWindows.append(overlay)
        }
    }

    private func performInstantOCR(rect: CGRect, screen: NSScreen) {
        Task {
            do {
                let screenFrame = screen.frame
                // rect is already in view-local coords (0..screenWidth, 0..screenHeight, bottom-left origin)
                // Only flip Y for ScreenCaptureKit (top-left origin)
                let screenRect = CGRect(
                    x: rect.origin.x,
                    y: screenFrame.height - rect.origin.y - rect.height,
                    width: rect.width,
                    height: rect.height
                )
                let displayID = screen.displayID

                let result = try await ScreenCaptureManager.captureArea(
                    rect: screenRect,
                    displayID: displayID
                )


                let text = try await TextRecognizer.recognizeText(
                    image: result.image,
                    keepLineBreaks: settings.ocrKeepLineBreaks
                )


                if text.isEmpty {
                    showToast("No text detected", icon: "info.circle.fill", iconColor: .systemYellow, screen: screen)
                } else {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    showToast("Copied \(text.count) characters", screen: screen)
                }
            } catch {

                showToast("OCR: \(error.localizedDescription)", icon: "xmark.circle.fill", iconColor: .systemRed, screen: screen)
            }
        }
    }

    // MARK: - Visual OCR

    /// - Parameter anchorScreen: The screen where the capture came from /
    ///   where the user was focused. When nil, the overlay falls back to the
    ///   primary display — use the nil form only when we genuinely don't know
    ///   (e.g. menu-bar invocation with no prior anchor).
    func startVisualOCR(image: CGImage, anchorScreen: NSScreen? = nil) {
        if !settings.ocrOnboardingShown {
            showOnboarding { [weak self] in
                self?.beginVisualOCR(image: image, anchorScreen: anchorScreen)
            }
        } else {
            beginVisualOCR(image: image, anchorScreen: anchorScreen)
        }
    }

    private func beginVisualOCR(image: CGImage, anchorScreen: NSScreen?) {
        Task {
            do {
                let regions = try await TextRecognizer.recognize(
                    image: image,
                    detectURLs: settings.ocrDetectLinks
                )

                if regions.isEmpty {
                    showToast("No text detected", icon: "info.circle.fill", iconColor: .systemYellow)
                    return
                }

                showOCROverlay(image: image, regions: regions, anchorScreen: anchorScreen)
            } catch {
                logger.error("Visual OCR failed: \(error.localizedDescription, privacy: .public)")
                showToast("OCR: \(error.localizedDescription)", icon: "xmark.circle.fill", iconColor: .systemRed)
            }
        }
    }

    private func showOCROverlay(image: CGImage, regions: [TextRegion], anchorScreen: NSScreen?) {
        ocrOverlayWindow?.close()
        ocrOverlayWindow = OCROverlayWindow(image: image, regions: regions, anchorScreen: anchorScreen)
        ocrOverlayWindow?.onClose = { [weak self] in
            self?.ocrOverlayWindow = nil
        }
        ocrOverlayWindow?.show()
    }

    // MARK: - Onboarding

    private func showOnboarding(then action: @escaping () -> Void) {
        onboardingWindow = OCROnboardingWindow(onDismiss: { [weak self] in
            self?.settings.ocrOnboardingShown = true
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            action()
        })
        onboardingWindow?.show()
    }

    // MARK: - Helpers

    private func dismissOverlay() {
        for window in overlayWindows {
            window.deactivate()
        }
        overlayWindows.removeAll()
    }

    private func showToast(_ message: String, icon: String = "checkmark.circle.fill", iconColor: NSColor = .systemGreen, screen: NSScreen? = nil) {
        toastWindow?.orderOut(nil)
        toastWindow = ToastWindow(message: message, icon: icon, iconColor: iconColor, screen: screen)
        toastWindow?.show()
    }
}
