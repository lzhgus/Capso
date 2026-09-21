// App/Sources/AnnotationEditor/BeautifyPanel.swift
import SwiftUI

struct BeautifyPanel: View {
    @Binding var settings: BeautifySettings

    // Curated palette: 4 neutrals + 4 soft pastels. The full macOS colour
    // picker is still available next to the swatches for anything else.
    private let presetColors: [Color] = [
        .white,
        Color(nsColor: NSColor(calibratedWhite: 0.96, alpha: 1)),
        Color(nsColor: NSColor(calibratedWhite: 0.18, alpha: 1)),
        .black,
        Color(nsColor: NSColor(srgbRed: 0.729, green: 0.902, blue: 0.992, alpha: 1)), // sky blue
        Color(nsColor: NSColor(srgbRed: 0.996, green: 0.843, blue: 0.663, alpha: 1)), // peach
        Color(nsColor: NSColor(srgbRed: 0.733, green: 0.969, blue: 0.816, alpha: 1)), // mint
        Color(nsColor: NSColor(srgbRed: 0.867, green: 0.839, blue: 0.996, alpha: 1)), // lavender
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Enable background", isOn: $settings.isEnabled)

            if settings.isEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    // -- Appearance --
                    settingRow("Style") {
                        Picker("", selection: $settings.backgroundStyle) {
                            ForEach(BeautifyBackgroundStyle.allCases) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }

                    if settings.backgroundStyle == .solid {
                        settingRow("Background") {
                            HStack(spacing: 4) {
                                ForEach(Array(presetColors.enumerated()), id: \.offset) { _, color in
                                    colorSwatch(color)
                                }
                                ColorPicker("", selection: $settings.backgroundColor, supportsOpacity: false)
                                    .labelsHidden()
                            }
                        }
                    }

                    if settings.backgroundStyle == .gradient {
                        settingRow("Gradient") {
                            HStack(spacing: 4) {
                                ForEach(BeautifyGradientPreset.allCases) { preset in
                                    gradientSwatch(preset)
                                }
                            }
                        }
                    }

                    Divider()
                        .padding(.vertical, 1)

                    // -- Dimensions --
                    sliderRow("Padding", value: $settings.padding, range: 16...80)
                    sliderRow("Corners", value: $settings.cornerRadius, range: 0...24)

                    Divider()
                        .padding(.vertical, 1)

                    // -- Shadow --
                    HStack(spacing: 8) {
                        Toggle(isOn: $settings.shadowEnabled) {
                            Text("Shadow")
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 80, alignment: .leading)

                        Slider(value: $settings.shadowRadius, in: 0...40, step: 1)
                            .disabled(!settings.shadowEnabled)

                        valueLabel(Int(settings.shadowRadius))
                    }
                    .opacity(settings.shadowEnabled ? 1 : 0.55)
                    .animation(.easeInOut(duration: 0.15), value: settings.shadowEnabled)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .animation(.easeInOut(duration: 0.2), value: settings.isEnabled)
        .animation(.easeInOut(duration: 0.15), value: settings.backgroundStyle)
    }

    // MARK: - Reusable Components

    private func settingRow<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func sliderRow(
        _ title: LocalizedStringKey,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Slider(value: value, in: range, step: 1)
            valueLabel(Int(value.wrappedValue))
        }
    }

    private func valueLabel(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: 28, alignment: .trailing)
    }

    private func colorSwatch(_ color: Color) -> some View {
        let selected = isColorMatch(color, settings.backgroundColor)
        return Button {
            settings.backgroundColor = color
        } label: {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .padding(2)
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: selected ? 1.5 : 0)
                )
        }
        .buttonStyle(.plain)
    }

    private func gradientSwatch(_ preset: BeautifyGradientPreset) -> some View {
        let selected = settings.gradientPreset == preset
        return Button {
            settings.gradientPreset = preset
        } label: {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(nsColor: preset.from), Color(nsColor: preset.to)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .padding(2)
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: selected ? 1.5 : 0)
                )
        }
        .buttonStyle(.plain)
        .help(preset.label)
        .accessibilityLabel(Text(preset.label))
    }

    private func isColorMatch(_ a: Color, _ b: Color) -> Bool {
        guard let c1 = NSColor(a).usingColorSpace(.sRGB),
              let c2 = NSColor(b).usingColorSpace(.sRGB) else { return false }
        return abs(c1.redComponent - c2.redComponent) < 0.02
            && abs(c1.greenComponent - c2.greenComponent) < 0.02
            && abs(c1.blueComponent - c2.blueComponent) < 0.02
    }
}
