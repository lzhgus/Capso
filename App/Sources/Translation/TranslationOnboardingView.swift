// App/Sources/Translation/TranslationOnboardingView.swift
import SwiftUI

struct TranslationOnboardingView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("How to use Translate")
                    .font(.system(size: 24, weight: .bold))
                Text("Translate text from any screenshot without leaving Capso")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            HStack(spacing: 16) {
                stepCard(
                    number: "01",
                    title: "Capture & Translate",
                    description: "Press ⌘⇧T, drag to select text",
                    symbol: "rectangle.dashed.and.paperclip",
                    symbolColor: .orange
                )
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
                stepCard(
                    number: "02",
                    title: "On-device",
                    description: "Apple Translation runs locally, privately",
                    symbol: "cpu",
                    symbolColor: .orange
                )
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
                stepCard(
                    number: "03",
                    title: "Read or Pin",
                    description: "Translation copies to clipboard; pin to keep",
                    symbol: "pin.square",
                    symbolColor: .orange
                )
            }

            Button("Got it!") { onDismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
        .frame(width: 700, height: 380)
    }

    private func stepCard(
        number: String,
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        symbol: String,
        symbolColor: Color
    ) -> some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.12), Color(white: 0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: symbol)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(symbolColor.opacity(0.85))
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(height: 140)

            VStack(spacing: 4) {
                Text("STEP \(number)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.orange)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
