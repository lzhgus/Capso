import AppKit
import SwiftUI
import AnnotationKit

struct AnnotationColorControls: View {
    @Binding var currentColor: AnnotationColor

    var swatchSize: CGFloat = 19
    var spacing: CGFloat = 3
    var selectedRingColor: Color = .accentColor

    @State private var sampler: NSColorSampler?
    @StateObject private var colorPanel = AnnotationColorPanelController()

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(AnnotationColor.allCases, id: \.self) { color in
                Button(action: { currentColor = color }) {
                    Circle()
                        .fill(Color(cgColor: color.cgColor))
                        .frame(width: swatchSize, height: swatchSize)
                        .overlay(Circle().stroke(currentColor == color ? selectedRingColor : Color.clear, lineWidth: 2))
                        .overlay(Circle().stroke(Color.black.opacity(0.24), lineWidth: 0.5))
                        .padding(2)
                        .background(
                            Circle()
                                .fill(currentColor == color ? selectedRingColor.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(Text(color.displayName))
            }

            Button(action: showCustomColorPanel) {
                ZStack {
                    Circle()
                        .fill(Color(nsColor: currentColor.nsColor))
                        .overlay(Circle().stroke(Color.black.opacity(0.28), lineWidth: 0.5))
                        .overlay(Circle().stroke(selectedRingColor.opacity(0.55), lineWidth: 1.5))

                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: max(10, swatchSize - 8), weight: .semibold))
                        .foregroundStyle(readableGlyphColor(for: currentColor.nsColor))
                }
                .frame(width: swatchSize + 8, height: swatchSize + 8)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Custom Color")

            Button(action: pickScreenColor) {
                Image(systemName: "eyedropper")
                    .font(.system(size: max(12, swatchSize - 6), weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.88))
                    .frame(width: swatchSize + 8, height: swatchSize + 8)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Pick Color From Screen")

            Button(action: copyCurrentHex) {
                Text(currentColor.hexRGB)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, height: swatchSize + 8)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Copy HEX Color")
        }
    }

    private func showCustomColorPanel() {
        colorPanel.show(initialColor: currentColor.nsColor) { color in
            currentColor = AnnotationColor(nsColor: color)
        }
    }

    private func pickScreenColor() {
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { color in
            if let color {
                currentColor = AnnotationColor(nsColor: color)
            }
            self.sampler = nil
        }
    }

    private func copyCurrentHex() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(currentColor.hexRGB, forType: .string)
    }

    private func readableGlyphColor(for color: NSColor) -> Color {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let luminance = (0.299 * rgb.redComponent) + (0.587 * rgb.greenComponent) + (0.114 * rgb.blueComponent)
        return luminance > 0.62 ? Color.black.opacity(0.72) : Color.white.opacity(0.92)
    }
}

@MainActor
private final class AnnotationColorPanelController: NSObject, ObservableObject {
    private var onChange: ((NSColor) -> Void)?

    func show(initialColor: NSColor, onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange

        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = initialColor
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(sender.color)
    }
}
