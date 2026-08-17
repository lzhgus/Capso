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

struct TranslationRequestGeneration {
    private var current: UUID?

    mutating func begin() -> UUID {
        let requestID = UUID()
        current = requestID
        return requestID
    }

    func isCurrent(_ requestID: UUID) -> Bool {
        current == requestID
    }

    mutating func invalidate() {
        current = nil
    }
}

@MainActor
@Observable
final class TranslationCoordinator {
    private let settings: AppSettings
    private var overlayWindows: [CaptureOverlayWindow] = []
    private var onboardingWindow: TranslationOnboardingWindow?
    private var typedInputWindow: TypedTranslationInputWindow?
    private var resultWindow: TranslationResultWindow?
    private var toastWindow: ToastWindow?
    private var translationTask: Task<Void, Never>?
    private var translationGeneration = TranslationRequestGeneration()

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

    func translateSelectedText() {
        if !settings.translationOnboardingShown {
            showOnboarding { [weak self] in self?.beginSelectedTextFlow() }
        } else {
            beginSelectedTextFlow()
        }
    }

    func translateTypedText() {
        typedInputWindow?.close()
        let window = TypedTranslationInputWindow(
            onSubmit: { [weak self] text in
                self?.submitTypedText(text)
            },
            onCancel: { [weak self] in
                self?.typedInputWindow?.close()
                self?.typedInputWindow = nil
            },
            onClose: { [weak self] in
                self?.typedInputWindow = nil
            }
        )
        typedInputWindow = window
        window.show()
    }

    /// - Parameter anchorScreen: The screen where the capture came from.
    ///   Used to place the result card on the correct display — without this,
    ///   translating a screenshot taken on a secondary screen would bounce the
    ///   card back to the primary.
    func translate(image: CGImage, anchorScreen: NSScreen? = nil) {
        if !settings.translationOnboardingShown {
            showOnboarding { [weak self] in
                self?.startImageTranslation(image: image, anchor: nil, anchorScreen: anchorScreen)
            }
        } else {
            startImageTranslation(image: image, anchor: nil, anchorScreen: anchorScreen)
        }
    }

    // MARK: - Capture flow

    private func beginCaptureFlow() {
        dismissOverlay()
        for screen in NSScreen.screens {
            let overlay = CaptureOverlayWindow(
                screen: screen,
                settings: settings,
                handlesGlobalKeyEvents: overlayWindows.isEmpty,
                presetsDisabled: true
            )
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
        let requestID = beginTranslationRequest()
        translationTask = Task { [weak self] in
            guard let self else { return }
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
                guard translationGeneration.isCurrent(requestID), !Task.isCancelled else { return }
                performTranslation(
                    image: result.image,
                    anchor: screenAnchor,
                    anchorScreen: screen,
                    requestID: requestID
                )
            } catch {
                guard translationGeneration.isCurrent(requestID), !Task.isCancelled else { return }
                translationTask = nil
                translationGeneration.invalidate()
                showToast("Translation: \(error.localizedDescription)", icon: "xmark.circle.fill", iconColor: .systemRed, screen: screen)
            }
        }
    }

    // MARK: - Translation (OCR only; actual translation runs in the card)

    private func startImageTranslation(image: CGImage, anchor: NSRect?, anchorScreen: NSScreen?) {
        let requestID = beginTranslationRequest()
        performTranslation(
            image: image,
            anchor: anchor,
            anchorScreen: anchorScreen,
            requestID: requestID
        )
    }

    private func performTranslation(
        image: CGImage,
        anchor: NSRect?,
        anchorScreen: NSScreen?,
        requestID: UUID
    ) {
        guard translationGeneration.isCurrent(requestID) else { return }
        let window = makeResultWindow(anchor: anchor, anchorScreen: anchorScreen)
        window.showRecognizing()

        translationTask = Task { [weak self, weak window] in
            guard let self else { return }
            do {
                let regions = try await TextRecognizer.recognize(image: image, detectURLs: false)
                guard let window,
                      translationGeneration.isCurrent(requestID),
                      resultWindow === window else { return }
                if regions.isEmpty {
                    closeResultWindow(window)
                    showToast(
                        "No text detected",
                        icon: "info.circle.fill",
                        iconColor: .systemYellow,
                        screen: anchorScreen
                    )
                    return
                }
                let target = settings.translationTargetLanguage
                showTranslation(
                    in: window,
                    regions: regions,
                    target: target,
                    anchor: anchor,
                    anchorScreen: anchorScreen
                )
                translationTask = nil
            } catch {
                guard let window,
                      translationGeneration.isCurrent(requestID),
                      resultWindow === window,
                      !Task.isCancelled else { return }
                closeResultWindow(window)
                showToast(
                    "OCR failed: \(error.localizedDescription)",
                    icon: "xmark.circle.fill",
                    iconColor: .systemRed,
                    screen: anchorScreen
                )
                logger.error("OCR error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func showLoadingResult(regions: [TextRegion], target: String, anchor: NSRect?, anchorScreen: NSScreen?) {
        let window = makeResultWindow(anchor: anchor, anchorScreen: anchorScreen)
        showTranslation(
            in: window,
            regions: regions,
            target: target,
            anchor: anchor,
            anchorScreen: anchorScreen
        )
    }

    private func makeResultWindow(anchor: NSRect?, anchorScreen: NSScreen?) -> TranslationResultWindow {
        resultWindow?.close()
        let window = TranslationResultWindow(
            settings: settings,
            anchor: anchor,
            anchorScreen: anchorScreen
        )
        window.onClose = { [weak self, weak window] in
            guard let self, let window, self.resultWindow === window else { return }
            self.closeResultWindow(window)
        }
        window.onPinChanged = { [weak self, weak window] isPinned in
            guard let self, let window, self.resultWindow === window else { return }
            // `.screenSaver` floats above everything — including other apps'
            // windows — making the translation card genuinely always-on-top
            // when pinned. Unpinning returns to regular floating level.
            window.setPinned(isPinned)
            window.level = isPinned ? .screenSaver : .floating
        }
        resultWindow = window
        return window
    }

    private func showTranslation(
        in window: TranslationResultWindow,
        regions: [TextRegion],
        target: String,
        anchor: NSRect?,
        anchorScreen: NSScreen?
    ) {
        window.onChangeLanguage = { [weak self, weak window] in
            guard let self, let window, self.resultWindow === window else { return }
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

            Task { @MainActor [weak self, weak window] in
                guard let self, let window, self.resultWindow === window else { return }
                let supportedCodes = await Self.loadSupportedLanguageCodes(fallback: fallbackCodes)
                guard self.resultWindow === window else { return }
                let popover = NSPopover()
                let picker = TranslationLanguagePickerPopover(
                    current: target,
                    available: supportedCodes
                ) { [weak self, weak window] newCode in
                    popover.performClose(nil)
                    guard let self, let window, self.resultWindow === window else { return }
                    _ = self.beginTranslationRequest()
                    self.showLoadingResult(regions: regions, target: newCode, anchor: anchor, anchorScreen: anchorScreen)
                }
                popover.contentViewController = NSHostingController(rootView: picker)
                popover.behavior = .transient
                if let contentView = window.contentView {
                    popover.show(
                        relativeTo: contentView.bounds,
                        of: contentView,
                        preferredEdge: .maxY
                    )
                }
            }
        }
        window.showTranslation(
            regions: regions,
            target: target,
            provider: settings.translationProvider,
            providerConfig: providerConfig()
        )
    }

    private func closeResultWindow(_ window: TranslationResultWindow) {
        guard resultWindow === window else { return }
        translationTask?.cancel()
        translationTask = nil
        translationGeneration.invalidate()
        window.close()
        resultWindow = nil
    }

    private func beginSelectedTextFlow() {
        let requestID = beginTranslationRequest()
        translationTask = Task { [weak self] in
            guard let self else { return }
            guard AXIsProcessTrusted() else {
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
                NotificationCenter.default.post(name: .openPreferencesTab, object: PreferencesTab.permissions)
                NSWorkspace.shared.open(PermissionKind.accessibility.settingsURL)
                showToast("Allow Accessibility to translate selected text", icon: "lock.fill", iconColor: .systemYellow)
                finishTranslationRequest(requestID)
                return
            }

            guard let text = await SelectedTextReader.readSelectedText(),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                guard translationGeneration.isCurrent(requestID), !Task.isCancelled else { return }
                showToast("No selected text found", icon: "text.cursor", iconColor: .systemYellow)
                finishTranslationRequest(requestID)
                return
            }

            guard translationGeneration.isCurrent(requestID), !Task.isCancelled else { return }
            let region = TextRegion(text: text, boundingBox: .zero, confidence: 1)
            let (anchor, screen) = Self.mouseAnchor()
            showLoadingResult(
                regions: [region],
                target: settings.translationTargetLanguage,
                anchor: anchor,
                anchorScreen: screen
            )
            translationTask = nil
        }
    }

    private func submitTypedText(_ text: String) {
        do {
            let region = try TypedTranslationInput(rawText: text).makeTextRegion()
            typedInputWindow?.close()
            typedInputWindow = nil
            _ = beginTranslationRequest()
            showLoadingResult(
                regions: [region],
                target: settings.translationTargetLanguage,
                anchor: nil,
                anchorScreen: NSScreen.main
            )
        } catch {
            showToast(error.localizedDescription, icon: "text.cursor", iconColor: .systemYellow)
        }
    }

    private func providerConfig() -> TranslationProviderConfiguration {
        TranslationProviderConfiguration(
            apiKey: settings.translationAPIKey() ?? "",
            endpoint: settings.translationProviderEndpoint,
            model: settings.translationProviderModel
        )
    }

    @discardableResult
    private func beginTranslationRequest() -> UUID {
        translationTask?.cancel()
        translationTask = nil
        resultWindow?.close()
        resultWindow = nil
        return translationGeneration.begin()
    }

    private func finishTranslationRequest(_ requestID: UUID) {
        guard translationGeneration.isCurrent(requestID) else { return }
        translationTask = nil
        translationGeneration.invalidate()
    }

    private static func mouseAnchor() -> (NSRect, NSScreen?) {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
        return (NSRect(x: point.x, y: point.y, width: 1, height: 1), screen)
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
