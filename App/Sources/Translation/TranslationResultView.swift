// App/Sources/Translation/TranslationResultView.swift
import SwiftUI
import Translation
import NaturalLanguage
import AppKit
import OCRKit
import SharedKit
import TranslationKit

struct TranslationResultView: View {
    let regions: [TextRegion]
    let target: String
    let provider: TranslationProviderKind
    let providerConfig: TranslationProviderConfiguration
    let autoCopy: Bool
    let showOriginal: Bool
    let onClose: () -> Void
    let onPinChanged: (Bool) -> Void
    let onChangeLanguage: () -> Void

    enum Phase {
        case loading
        case streaming(TranslatedRegion)
        case done([TranslatedRegion])
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var runConfig: TranslationSession.Configuration?
    @State private var originalExpanded: Bool = false
    @State private var isPinned: Bool = false
    @State private var manualCopyShown: Bool = false
    @State private var providerTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(detectedCode: currentDetectedCode)

            // One scrollview wraps the variable-height middle. Header & footer stay pinned.
            ScrollView(.vertical, showsIndicators: true) {
                middleContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer(copiedMessage: shouldShowCopied ? "Copied" : nil)
        }
        .frame(width: 420, height: 520)
        .background(hiddenEscape)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .onAppear { startTranslation() }
        .onDisappear { providerTask?.cancel() }
        .translationTask(runConfig) { session in
            await runTranslation(using: session)
        }
    }

    // MARK: - Middle content (inside scrollview)

    @ViewBuilder
    private var middleContent: some View {
        switch phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Translating…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        case .done(let regions):
            doneSections(region: regions.first)
        case .streaming(let region):
            streamingSection(region: region)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
    }

    private func doneSections(region: TranslatedRegion?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let region {
                // TRANSLATION first
                sectionLabel("TRANSLATION")
                renderedText(
                    region.translation,
                    bodyFont: .system(size: 15, weight: .medium),
                    bodyColor: .primary,
                    markerColor: .tertiary
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

                Divider().padding(.horizontal, 12)

                if showOriginal {
                    // ORIGINAL (collapsible)
                    HStack(spacing: 8) {
                        Button(action: toggleOriginal) {
                            HStack(spacing: 8) {
                                Text("ORIGINAL")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .tracking(1.0)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(originalExpanded ? 90 : 0))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)

                        Button(action: { copyText(region.original.text) }) {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .help("Copy original")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if originalExpanded {
                        renderedText(
                            region.original.text,
                            bodyFont: .system(size: 13),
                            bodyColor: .secondary,
                            markerColor: .tertiary
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    private func streamingSection(region: TranslatedRegion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("TRANSLATION")
            Text(region.translation)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Translating…")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func renderedText<BC: ShapeStyle, MC: ShapeStyle>(
        _ text: String,
        bodyFont: Font,
        bodyColor: BC,
        markerColor: MC
    ) -> some View {
        let blocks = TranslationTextBlockParser.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let body):
                    Text(body)
                        .font(bodyFont)
                        .foregroundStyle(bodyColor)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                case .bulletList(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("•")
                                    .font(bodyFont)
                                    .foregroundStyle(markerColor)
                                    .frame(width: 10, alignment: .center)
                                Text(item)
                                    .font(bodyFont)
                                    .foregroundStyle(bodyColor)
                                    .lineSpacing(3)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                case .numberedList(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(item.number).")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(markerColor)
                                    .frame(width: 22, alignment: .trailing)
                                Text(item.text)
                                    .font(bodyFont)
                                    .foregroundStyle(bodyColor)
                                    .lineSpacing(3)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Chrome (pinned)

    private func header(detectedCode: String?) -> some View {
        HStack(spacing: 10) {
            closeDot
            Spacer()
            Button(action: onChangeLanguage) {
                Text(languagePair(detectedCode: detectedCode))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: togglePin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(isPinned ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Unpin" : "Pin to screen")
            Button(action: copyCurrent) { Image(systemName: "doc.on.doc") }
                .buttonStyle(.plain)
                .help("Copy translation")
                .keyboardShortcut("c", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(Divider().padding(.horizontal, 12), alignment: .bottom)
    }

    private func footer(copiedMessage: String?) -> some View {
        HStack {
            Text(provider.displayName)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            if let copiedMessage {
                Circle().fill(Color.green).frame(width: 4, height: 4)
                Text(LocalizedStringKey(copiedMessage))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(autoCopy ? "Esc" : "⌘C  Esc")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.02))
        .overlay(Divider().padding(.horizontal, 12), alignment: .top)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(1.0)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private var closeDot: some View {
        Button(action: onClose) {
            Circle()
                .fill(Color.red.opacity(0.9))
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Close")
    }

    private func languagePair(detectedCode: String?) -> String {
        let source = detectedCode?.uppercased() ?? "—"
        let targetName = Locale.current.localizedString(forIdentifier: target) ?? target
        return "\(source) → \(targetName)"
    }

    private func toggleOriginal() {
        withAnimation(.easeOut(duration: 0.22)) {
            originalExpanded.toggle()
        }
    }

    private func togglePin() {
        isPinned.toggle()
        onPinChanged(isPinned)
    }

    // MARK: - Derived state

    private var currentDetectedCode: String? {
        if case .done(let regions) = phase {
            return regions.first?.detectedSource.languageCode?.identifier
        }
        if case .streaming(let region) = phase {
            return region.detectedSource.languageCode?.identifier
        }
        return nil
    }

    private var isDone: Bool {
        if case .done = phase { return true }
        return false
    }

    private var shouldShowCopied: Bool {
        if autoCopy && isDone { return true }
        return manualCopyShown
    }

    // MARK: - Logic

    private func buildConfig() {
        let combined = sourceText
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(combined)
        let detected = recognizer.dominantLanguage?.rawValue

        // Pre-check: if NLLanguageRecognizer confidently detected the source
        // and it already matches the target, Apple's TranslationSession would
        // fail with a generic "Unable to Translate" — surface a helpful message
        // BEFORE calling Apple at all.
        if let detected, Self.normalizedCode(detected) == Self.normalizedCode(target) {
            let name = Locale.current.localizedString(forIdentifier: target) ?? target
            phase = .failed("Source is already \(name). Change target via the language pill above.")
            runConfig = nil   // don't trigger the translationTask
            return
        }

        let sourceLanguage = detected.map { Locale.Language(identifier: $0) }
        let targetLanguage = Locale.Language(identifier: target)
#if compiler(>=6.2)
        if #available(macOS 26.4, *) {
            runConfig = TranslationSession.Configuration(
                source: sourceLanguage,
                target: targetLanguage,
                preferredStrategy: .highFidelity
            )
            return
        }
#endif
        runConfig = TranslationSession.Configuration(
            source: sourceLanguage,
            target: targetLanguage
        )
    }

    private func startTranslation() {
        originalExpanded = showOriginal
        guard provider == .apple else {
            runConfig = nil
            providerTask?.cancel()
            providerTask = Task { await runProviderTranslation() }
            return
        }
        buildConfig()
    }

    /// Normalizes codes for comparison (e.g. NLLanguageRecognizer returns
    /// "zh-Hans" / "zh-Hant"; our target stores the same form). Makes matching
    /// robust to minor casing/encoding differences.
    private static func normalizedCode(_ code: String) -> String {
        code.lowercased()
    }

    private func runTranslation(using session: TranslationSession) async {
        let joinedOriginal = sourceText
        guard !joinedOriginal.isEmpty else {
            phase = .failed("No text to translate")
            return
        }

        nonisolated(unsafe) let s = session
        do {
            let response = try await s.translate(joinedOriginal)
            let translation = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            let detectedSource = response.sourceLanguage.languageCode?.identifier ?? ""

            if !detectedSource.isEmpty && detectedSource == target {
                let name = Locale.current.localizedString(forIdentifier: target) ?? target
                phase = .failed("Source is already \(name). Change target via the language pill above.")
                return
            }

            if translation.isEmpty {
                phase = .failed("Translation returned no results. Try changing the target language.")
                return
            }

            if autoCopy {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(response.targetText, forType: .string)
            }

            let merged = TextRegion(
                text: joinedOriginal,
                boundingBox: firstMeaningfulRegion?.boundingBox ?? .zero,
                confidence: 1.0
            )
            let result = TranslatedRegion(
                original: merged,
                translation: response.targetText,
                detectedSource: Locale.Language(identifier: detectedSource.isEmpty ? "en" : detectedSource)
            )
            phase = .done([result])
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func runProviderTranslation() async {
        let joinedOriginal = sourceText
        guard !joinedOriginal.isEmpty else {
            phase = .failed("No text to translate")
            return
        }
        let merged = TextRegion(
            text: joinedOriginal,
            boundingBox: firstMeaningfulRegion?.boundingBox ?? .zero,
            confidence: 1.0
        )
        do {
            var response: ProviderTranslationResult?
            for try await update in ProviderTranslationService.translationUpdates(
                text: joinedOriginal,
                target: target,
                provider: provider,
                config: providerConfig
            ) {
                try Task.checkCancellation()
                response = update
                phase = .streaming(TranslatedRegion(
                    original: merged,
                    translation: update.text,
                    detectedSource: Locale.Language(identifier: update.detectedSource ?? "und")
                ))
            }
            guard let response, !response.text.isEmpty else {
                phase = .failed("Translation returned no results. Try changing the target language.")
                return
            }

            if autoCopy {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(response.text, forType: .string)
            }

            let result = TranslatedRegion(
                original: merged,
                translation: response.text,
                detectedSource: Locale.Language(identifier: response.detectedSource ?? "und")
            )
            phase = .done([result])
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func copyCurrent() {
        switch phase {
        case .streaming(let region):
            copyText(region.translation)
        case .done(let regions):
            guard let region = regions.first else { return }
            copyText(region.translation)
        case .loading, .failed:
            return
        }
    }

    private var sourceText: String {
        TranslationTextLayout.compose(regions.map {
            TranslationTextLine(text: $0.text, frame: $0.boundingBox)
        })
    }

    private var firstMeaningfulRegion: TextRegion? {
        regions.first {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func copyText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Show a brief "Copied" feedback so manual copy doesn't feel silent.
        // When `autoCopy` is on, the indicator is already visible; this still
        // re-asserts it, harmlessly.
        withAnimation(.easeOut(duration: 0.2)) {
            manualCopyShown = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeOut(duration: 0.3)) {
                manualCopyShown = false
            }
        }
    }

    private var hiddenEscape: some View {
        Button(action: onClose) { EmptyView() }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
    }
}
