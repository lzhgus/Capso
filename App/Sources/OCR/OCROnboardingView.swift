// App/Sources/OCR/OCROnboardingView.swift
import SwiftUI

struct OCROnboardingView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("How to use Text Recognition")
                    .font(.system(size: 24, weight: .bold))

                Text("Copy non-selectable text from images, videos, and webpages")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            HStack(spacing: 16) {
                StepCard(
                    number: "01",
                    title: "Select Area",
                    description: "Drag crosshair to select the region containing text",
                    animation: .selection
                )

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)

                StepCard(
                    number: "02",
                    title: "Scan & Recognize",
                    description: "Text is automatically detected and recognized",
                    animation: .scanning
                )

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)

                StepCard(
                    number: "03",
                    title: "Auto-Copy",
                    description: "Recognized text is instantly copied to your clipboard",
                    animation: .toast
                )
            }

            Button("Got it!") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 700, height: 420)
    }
}

// MARK: - Step Card

private enum StepAnimation {
    case selection
    case scanning
    case toast
}

private struct StepCard: View {
    let number: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let animation: StepAnimation

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.1))

                switch animation {
                case .selection:
                    SelectionAnimation()
                case .scanning:
                    ScanAnimation()
                case .toast:
                    ToastAnimation()
                }
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(spacing: 4) {
                Text("STEP \(number)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.blue)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Selection Animation

private struct SelectionAnimation: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: CGFloat([100, 120, 80, 110][i]), height: 8)
                }
            }

            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.blue, lineWidth: 2)
                .frame(
                    width: animate ? 130 : 0,
                    height: animate ? 70 : 0
                )
                .opacity(animate ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Scan Animation

private struct ScanAnimation: View {
    @State private var scanOffset: CGFloat = 0

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    let lineY = CGFloat(i) * 18
                    RoundedRectangle(cornerRadius: 3)
                        .fill(lineY < scanOffset ? Color.blue.opacity(0.3) : Color.white.opacity(0.08))
                        .frame(width: CGFloat([100, 130, 90, 120, 105][i]), height: 8)
                        .animation(.easeOut(duration: 0.2), value: scanOffset)
                }
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .blue.opacity(0.6), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .shadow(color: .blue.opacity(0.5), radius: 8)
                .offset(y: scanOffset - 50)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false)) {
                scanOffset = 100
            }
        }
    }
}

// MARK: - Toast Animation

private struct ToastAnimation: View {
    @State private var showToast = false

    var body: some View {
        ZStack {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                Text("Copied 247 chars")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .offset(y: showToast ? 0 : 20)
            .opacity(showToast ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).repeatForever(autoreverses: true).delay(0.3)) {
                showToast = true
            }
        }
    }
}
