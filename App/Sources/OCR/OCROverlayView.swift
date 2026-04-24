// App/Sources/OCR/OCROverlayView.swift
import SwiftUI
import OCRKit

struct OCROverlayView: View {
    let image: CGImage
    let regions: [TextRegion]
    let onClose: () -> Void

    @State private var selectedID: UUID?
    @State private var copiedID: UUID?

    private var imageSize: CGSize {
        CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
    }

    var body: some View {
        HStack(spacing: 0) {
            imagePanel
                .frame(minWidth: 400)
            Divider()
            textPanel
                .frame(width: 300)
        }
        .frame(minWidth: 700, minHeight: 400)
    }

    // MARK: - Image Panel

    private var imagePanel: some View {
        GeometryReader { geo in
            let scale = min(
                (geo.size.width - 32) / imageSize.width,
                (geo.size.height - 32) / imageSize.height,
                1.0
            )
            let scaledW = imageSize.width * scale
            let scaledH = imageSize.height * scale

            ZStack {
                Color(white: 0.12)

                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .frame(width: scaledW, height: scaledH)

                    ForEach(Array(regions.enumerated()), id: \.element.id) { index, region in
                        let rect = scaledRect(region.boundingBox, scale: scale)
                        RegionOverlay(
                            isSelected: selectedID == region.id,
                            isCopied: copiedID == region.id
                        )
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .onTapGesture { selectAndCopy(region) }
                    }
                }
                .frame(width: scaledW, height: scaledH)
            }
        }
    }

    private func scaledRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    // MARK: - Text Panel

    private var textPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recognized Text")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(regions.count) regions · \(totalChars) chars")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(regions) { region in
                        TextBlockView(
                            region: region,
                            isSelected: selectedID == region.id,
                            isCopied: copiedID == region.id
                        )
                        .onTapGesture { selectAndCopy(region) }
                    }
                }
                .padding(12)
            }

            Divider()

            HStack(spacing: 8) {
                Spacer()
                Button("Copy All") {
                    copyAll()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut("c", modifiers: .command)
            }
            .padding(12)
        }
        .background(.ultraThinMaterial)
    }

    private var totalChars: Int {
        regions.reduce(0) { $0 + $1.text.count }
    }

    // MARK: - Actions

    private func selectAndCopy(_ region: TextRegion) {
        selectedID = region.id
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(region.text, forType: .string)

        copiedID = region.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedID == region.id {
                copiedID = nil
            }
        }
    }

    private func copyAll() {
        let allText = regions.map(\.text).joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(allText, forType: .string)
        onClose()
    }
}

// MARK: - Region Overlay

private struct RegionOverlay: View {
    let isSelected: Bool
    let isCopied: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .shadow(color: shadowColor, radius: isSelected ? 6 : 0)
            .contentShape(Rectangle())
    }

    private var fillColor: Color {
        if isCopied || isSelected { return Color.green.opacity(0.15) }
        return Color.blue.opacity(0.1)
    }

    private var borderColor: Color {
        if isCopied || isSelected { return Color.green.opacity(0.6) }
        return Color.blue.opacity(0.4)
    }

    private var shadowColor: Color {
        if isCopied || isSelected { return Color.green.opacity(0.3) }
        return .clear
    }
}

// MARK: - Text Block

private struct TextBlockView: View {
    let region: TextRegion
    let isSelected: Bool
    let isCopied: Bool

    var body: some View {
        HStack {
            Text(region.text)
                .font(.system(size: 13))
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isCopied {
                Text("COPIED ✓")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.green)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private var backgroundColor: Color {
        if isCopied || isSelected { return Color.green.opacity(0.06) }
        return Color.white.opacity(0.04)
    }

    private var borderColor: Color {
        if isCopied || isSelected { return Color.green.opacity(0.25) }
        return Color.clear
    }
}
