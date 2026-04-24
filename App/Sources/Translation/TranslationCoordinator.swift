// App/Sources/Translation/TranslationCoordinator.swift
import AppKit
import SwiftUI
import Foundation
import Observation
import os.log
import Translation
import CaptureKit
import OCRKit
import SharedKit
import TranslationKit

private let logger = Logger(subsystem: "com.awesomemacapps.capso", category: "Translation")

@MainActor
@Observable
final class TranslationCoordinator {
    private let settings: AppSettings
    private var overlayWindows: [CaptureOverlayWindow] = []
    private var onboardingWindow: TranslationOnboardingWindow?
    private var resultWindow: TranslationResultWindow?
    private var toastWindow: ToastWindow?

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Entry points

    func startCaptureAndTranslate() {
        if !settings.translationOnboardingShown {
            showOnboarding { [weak self] in self?.beginCaptureFlow() }
        } else {
            beginCaptureFlow()
        }
    }

    /// - Parameter anchorScreen: The screen where the capture came from.
    ///   Used to place the result card on the correct display — without this,
    ///   translating a screenshot taken on a secondary screen would bounce the
    ///   card back to the primary.
    func translate(image: CGImage, anchorScreen: NSScreen? = nil) {
        if !settings.translationOnboardingShown {
            showOnboarding { [weak self] in
                self?.performTranslation(image: image, anchor: nil, anchorScreen: anchorScreen)
            }
        } else {
            performTranslation(image: image, anchor: nil, anchorScreen: anchorScreen)
        }
    }

    // MARK: - Capture flow

    private func beginCaptureFlow() {
        dismissOverlay()
        for screen in NSScreen.screens {
            let overlay = CaptureOverlayWindow(screen: screen, settings: settings, presetsDisabled: true)
            overlay.onAreaSelected = { [weak self] rect, screen in
                self?.dismissOverlay()
                self?.captureAndPerform(rect: rect, screen: screen)
            }
            overlay.onCancelled = { [weak self] in self?.dismissOverlay() }
            overlay.activate(mode: .area)
            overlayWindows.append(overlay)
        }
    }

    private func captureAndPerform(rect: CGRect, screen: NSScreen) {
        Task {
            do {
                let screenFrame = screen.frame
                let screenRect = CGRect(
                    x: rect.origin.x,
                    y: screenFrame.height - rect.origin.y - rect.height,
                    width: rect.width,
                    height: rect.height
                )
                let result = try await ScreenCaptureManager.captureArea(
                    rect: screenRect,
                    displayID: screen.displayID
                )
                // Convert the overlay-local rect to screen-absolute coordinates
                // so the card can be positioned on the correct screen.
                let screenAnchor = NSRect(
                    x: screen.frame.origin.x + rect.origin.x,
                    y: screen.frame.origin.y + rect.origin.y,
                    width: rect.width,
                    height: rect.height
                )
                performTranslation(
                    image: result.image,
                    anchor: screenAnchor,
                    anchorScreen: screen
                )
            } catch {
                showToast("Translation: \(error.localizedDescription)", icon: "xmark.circle.fill", iconColor: .systemRed, screen: screen)
            }
        }
    }

    // MARK: - Translation (OCR only; actual translation runs in the card)

    private func performTranslation(image: CGImage, anchor: NSRect?, anchorScreen: NSScreen? = nil) {
        Task {
            do {
                let regions = try await TextRecognizer.recognize(image: image, detectURLs: false)
                if regions.isEmpty {
                    showToast("No text detected", icon: "info.circle.fill", iconColor: .systemYellow)
                    return
                }
                let target = settings.translationTargetLanguage
                showLoadingResult(regions: regions, target: target, anchor: anchor, anchorScreen: anchorScreen)
            } catch {
                showToast(
                    "OCR failed: \(error.localizedDescription)",
                    icon: "xmark.circle.fill",
                    iconColor: .systemRed
                )
                logger.error("OCR error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func showLoadingResult(regions: [TextRegion], target: String, anchor: NSRect?, anchorScreen: NSScreen?) {
        resultWindow?.close()
        let window = TranslationResultWindow(
            regions: regions,
            target: target,
            settings: settings,
            anchor: anchor,
            anchorScreen: anchorScreen
        )
        window.onClose = { [weak self] in
            self?.resultWindow?.close()
            self?.resultWindow = nil
        }
        window.onPinChanged = { [weak self] isPinned in
            guard let window = self?.resultWindow else { return }
            // `.screenSaver` floats above everything — including other apps'
            // windows — making the translation card genuinely always-on-top
            // when pinned. Unpinning returns to regular floating level.
            window.level = isPinned ? .screenSaver : .floating
        }
        window.onChangeLanguage = { [weak self] in
            guard let self else { return }
            // Fall back includes all 20 macOS 15 target languages (adds th, vi
            // that the earlier list missed). Apple may add more in later
            // OS versions — `LanguageAvailability.supportedLanguages` gives
            // the authoritative runtime list.
            let fallbackCodes = [
                "ar", "de", "en", "es", "fr",
                "hi", "id", "it", "ja", "ko",
                "nl", "pl", "pt-BR", "ru", "th",
                "tr", "uk", "vi", "zh-Hans", "zh-Hant"
            ]

            Task { @MainActor in
                let supportedCodes = await Self.loadSupportedLanguageCodes(fallback: fallbackCodes)
                let popover = NSPopover()
                let picker = TranslationLanguagePickerPopover(
                    current: target,
                    available: supportedCodes
                ) { newCode in
                    popover.performClose(nil)
                    self.showLoadingResult(regions: regions, target: newCode, anchor: anchor, anchorScreen: anchorScreen)
                }
                popover.contentViewController = NSHostingController(rootView: picker)
                popover.behavior = .transient
                if let contentView = self.resultWindow?.contentView {
                    popover.show(
                        relativeTo: contentView.bounds,
                        of: contentView,
                        preferredEdge: .maxY
                    )
                }
            }
        }
        resultWindow = window
        window.show()
    }

    /// Fetches the authoritative list of target language BCP-47 codes from
    /// Apple's `LanguageAvailability`. Falls back to the passed list if the
    /// framework returns an empty set (shouldn't happen on supported macOS).
    ///
    /// `supportedLanguages` returns regional variants (e.g. en-US, en-GB, zh-Hans-CN,
    /// zh-Hant-TW). We deduplicate to unique canonical codes: language-only for most
    /// languages, language-script for Chinese (which has two distinct scripts).
    static func loadSupportedLanguageCodes(fallback: [String]) async -> [String] {
        // Create LanguageAvailability off the main actor to satisfy Swift 6
        // Sendable checking (LanguageAvailability is non-Sendable).
        let langs: [Locale.Language] = await Task.detached {
            let availability = LanguageAvailability()
            return await availability.supportedLanguages
        }.value
        if langs.isEmpty { return fallback }

        var seen = Set<String>()
        var result: [String] = []
        for lang in langs {
            guard let langCode = lang.languageCode?.identifier else { continue }
            let canonical: String
            if langCode == "zh", let script = lang.script?.identifier {
                // Distinguish Simplified (Hans) from Traditional (Hant).
                canonical = "\(langCode)-\(script)"
            } else if langCode == "pt", let region = lang.region?.identifier, region == "BR" {
                // Keep pt-BR distinct from pt-PT.
                canonical = "pt-BR"
            } else {
                canonical = langCode
            }
            guard !canonical.isEmpty, seen.insert(canonical).inserted else { continue }
            result.append(canonical)
        }
        return result.isEmpty ? fallback : result
    }

    // MARK: - Onboarding

    private func showOnboarding(then action: @escaping () -> Void) {
        onboardingWindow = TranslationOnboardingWindow(onDismiss: { [weak self] in
            guard let self else { return }
            self.settings.translationOnboardingShown = true
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
            DispatchQueue.main.async {
                action()
            }
        })
        onboardingWindow?.show()
    }

    // MARK: - Helpers

    private func dismissOverlay() {
        for w in overlayWindows { w.deactivate() }
        overlayWindows.removeAll()
    }

    private func showToast(
        _ message: String,
        icon: String = "checkmark.circle.fill",
        iconColor: NSColor = .systemGreen,
        screen: NSScreen? = nil
    ) {
        toastWindow?.orderOut(nil)
        toastWindow = ToastWindow(message: message, icon: icon, iconColor: iconColor, screen: screen)
        toastWindow?.show()
    }
}
