import SwiftUI
import EditorKit
import SharedKit

struct EditorSettingsPanel: View {
    @Bindable var coordinator: EditorCoordinator

    @State private var lastAutoZoomRun: AutoZoomRunResult = .idle
    @State private var autoZoomRevertTask: Task<Void, Never>?

    private enum AutoZoomRunResult: Equatable {
        case idle
        case ranEmpty   // 0 segments — show inline "no moments" hint for a few seconds
        case ranNonEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Effects")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.top, 4)

                backgroundSection
                zoomSection
                cursorSection
            }
            .padding(16)
        }
    }

    // MARK: - Background Section

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Background")

            settingCard {
                settingToggleRow(
                    "Enabled",
                    isOn: $coordinator.project.backgroundStyle.enabled
                )

                if coordinator.project.backgroundStyle.enabled {
                    cardDivider

                    // Color type picker
                    settingPickerRow("Style", selection: $coordinator.project.backgroundStyle.colorType) {
                        Text("Solid").tag(BackgroundColorType.solid)
                        Text("Gradient").tag(BackgroundColorType.gradient)
                        Text("Liquid Glass").tag(BackgroundColorType.liquidGlass)
                    }

                    cardDivider

                    // Color presets (only for solid fills)
                    if coordinator.project.backgroundStyle.colorType == .solid {
                        colorPresetRow
                    }

                    cardDivider

                    // Padding — vertical layout for full-width slider
                    verticalSliderRow(
                        "Padding",
                        value: $coordinator.project.backgroundStyle.padding,
                        range: 0...80,
                        unit: "px"
                    )

                    // Corner radius
                    verticalSliderRow(
                        "Corner Radius",
                        value: $coordinator.project.backgroundStyle.cornerRadius,
                        range: 0...BackgroundStyle.maxCornerRadius,
                        unit: "px"
                    )

                    cardDivider

                    // Shadow
                    settingToggleRow(
                        "Shadow",
                        isOn: $coordinator.project.backgroundStyle.shadowEnabled
                    )

                    if coordinator.project.backgroundStyle.shadowEnabled {
                        verticalSliderRow(
                            "Shadow Radius",
                            value: $coordinator.project.backgroundStyle.shadowRadius,
                            range: 0...30,
                            unit: "px"
                        )

                        verticalSliderRow(
                            "Shadow Opacity",
                            value: $coordinator.project.backgroundStyle.shadowOpacity,
                            range: 0...1,
                            unit: "",
                            precision: 2,
                            step: 0.05
                        )
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: coordinator.project.backgroundStyle.enabled)
            .animation(.easeInOut(duration: 0.15), value: coordinator.project.backgroundStyle.shadowEnabled)
        }
    }

    // MARK: - Color Presets
    //
    // 2×4 grid: 7 warm-desaturated presets + 1 custom-color cell that hands
    // off to SwiftUI's native `ColorPicker` (which uses the standard macOS
    // color panel). Palette and naming follow .impeccable.md — warm
    // restraint, no pure #000/#fff, no AI-slop gradients.

    /// The 7 presets, in grid order. A single source of truth — used both
    /// to render the swatches and to detect whether the current solid color
    /// falls outside the preset set (→ "Custom" cell shows active state).
    private static let solidColorPresets: [(color: CodableColor, label: LocalizedStringKey)] = [
        (.ink,   "Ink"),
        (.stone, "Stone"),
        (.mist,  "Mist"),
        (.sand,  "Sand"),
        (.dusk,  "Dusk"),
        (.sage,  "Sage"),
        (.clay,  "Clay"),
    ]

    private var colorPresetRow: some View {
        // Column-major-ish: presets fill rows left-to-right; the 8th cell
        // (bottom-right) is always the custom picker.
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { i in
                    colorPresetButton(
                        Self.solidColorPresets[i].color,
                        label: Self.solidColorPresets[i].label
                    )
                }
            }
            HStack(spacing: 10) {
                ForEach(4..<7, id: \.self) { i in
                    colorPresetButton(
                        Self.solidColorPresets[i].color,
                        label: Self.solidColorPresets[i].label
                    )
                }
                customColorCell
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func colorPresetButton(_ color: CodableColor, label: LocalizedStringKey) -> some View {
        let isSelected = coordinator.project.backgroundStyle.solidColor == color
        return Button {
            coordinator.project.backgroundStyle.solidColor = color
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: color.red, green: color.green, blue: color.blue))
                    .frame(width: 32, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.white.opacity(0.15),
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    )
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? .primary : .tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    /// "Custom" cell — a plain SwiftUI `Button` styled identically to the
    /// preset swatches. Tapping opens the shared `NSColorPanel` directly
    /// (skipping `ColorPicker` / `NSColorWell`, which impose their own
    /// chunky blue-ringed "active well" chrome that can't be styled away).
    ///
    /// States:
    ///   • Preset active → neutral `white.opacity(0.05)` fill + dim `+`
    ///     icon, 0.5pt `white.opacity(0.15)` border (matches unselected
    ///     preset chrome exactly).
    ///   • Custom active → cell filled with current color; 2pt
    ///     `Color.accentColor` border (matches selected preset chrome).
    private var customColorCell: some View {
        let currentColor = coordinator.project.backgroundStyle.solidColor
        let isCustom = !Self.solidColorPresets.contains { $0.color == currentColor }

        // Structure kept identical to `colorPresetButton` (which we know
        // is hittable) — Button wraps the whole VStack, swatch uses a
        // single RoundedRectangle with stacked .overlay modifiers. No
        // inner ZStack, no .contentShape: both interfered with Button hit
        // testing in the previous implementation and meant clicks were
        // dropped silently.
        return Button {
            openCustomColorPanel()
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isCustom
                            ? AnyShapeStyle(Color(red: currentColor.red, green: currentColor.green, blue: currentColor.blue))
                            : AnyShapeStyle(Color.white.opacity(0.05))
                    )
                    .frame(width: 32, height: 22)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .opacity(isCustom ? 0 : 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                isCustom ? Color.accentColor : Color.white.opacity(0.15),
                                lineWidth: isCustom ? 2 : 0.5
                            )
                    )

                Text("Custom")
                    .font(.system(size: 9))
                    .foregroundStyle(isCustom ? .primary : .tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    /// Open the shared `NSColorPanel` wired to the current solid color.
    /// `ColorPanelBridge` keeps a long-lived target/action the panel can
    /// notify as the user drags — we can't lean on closure capture because
    /// `NSColorPanel` uses @objc target/action and the panel outlives any
    /// transient closure.
    @MainActor
    private func openCustomColorPanel() {
        ColorPanelBridge.shared.coordinator = coordinator

        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        let current = coordinator.project.backgroundStyle.solidColor
        panel.color = NSColor(
            srgbRed: CGFloat(current.red),
            green: CGFloat(current.green),
            blue: CGFloat(current.blue),
            alpha: 1.0
        )
        // `NSColorPanel` exposes target/action via Objective-C setters
        // only — no Swift property form is synthesized for these (unlike
        // most NSControl subclasses). Use the explicit setter methods.
        panel.setTarget(ColorPanelBridge.shared)
        panel.setAction(#selector(ColorPanelBridge.colorPanelColorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Cursor Section

    private var cursorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Cursor")

            settingCard {
                settingToggleRow(
                    "Smoothing",
                    isOn: $coordinator.project.cursorSmoothing.enabled
                )

                if coordinator.project.cursorSmoothing.enabled {
                    cardDivider

                    settingPickerRow("Style", selection: smoothingPresetBinding) {
                        Text("Snappy").tag(CursorSmoothingPreset.snappy)
                        Text("Smooth").tag(CursorSmoothingPreset.smooth)
                        Text("Floaty").tag(CursorSmoothingPreset.floaty)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: coordinator.project.cursorSmoothing.enabled)
        }
    }

    // MARK: - Smoothing Preset

    private var smoothingPresetBinding: Binding<CursorSmoothingPreset> {
        Binding(
            get: {
                coordinator.project.cursorSmoothing.preset
            },
            set: { preset in
                coordinator.project.cursorSmoothing = preset.config
            }
        )
    }

    // MARK: - Zoom Section

    private var zoomSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Zoom")

            settingCard {
                autoZoomRow

                cardDivider

                HStack {
                    Text("Segments")
                        .font(.system(size: 13))
                    Spacer()
                    Text("\(coordinator.project.zoomSegments.count)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if let segment = coordinator.selectedZoomSegment {
                    cardDivider

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected Segment")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                    verticalSliderRow(
                        "Zoom Level",
                        value: zoomLevelBinding(for: segment.id),
                        range: 1.25...5.0,
                        unit: "x",
                        precision: 1,
                        step: 0.25
                    )

                    settingPickerRow("Focus", selection: focusModeBinding(for: segment.id)) {
                        Text("Follow Cursor").tag(ZoomFocusTag.followCursor)
                        Text("Center").tag(ZoomFocusTag.center)
                    }

                    cardDivider

                    Button(role: .destructive) {
                        coordinator.removeZoomSegment(id: segment.id)
                    } label: {
                        Label("Delete Segment", systemImage: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                } else {
                    cardDivider

                    Text("Double-click the zoom track to add segments.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    private var autoZoomRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text("Suggest zooms")
                    .font(.system(size: 13))
                Spacer()
                autoZoomButton
            }

            Text(autoZoomSubtext)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .animation(.easeInOut(duration: 0.2), value: lastAutoZoomRun)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var autoZoomSubtext: String {
        switch lastAutoZoomRun {
        case .ranEmpty:
            return String(localized: "No clear moments detected — try recording with more clicks.")
        case .idle, .ranNonEmpty:
            return String(localized: "Analyzes clicks + pauses.")
        }
    }

    private var autoZoomButton: some View {
        Button {
            let count = coordinator.autoZoom()
            lastAutoZoomRun = count > 0 ? .ranNonEmpty : .ranEmpty
            autoZoomRevertTask?.cancel()
            if count == 0 {
                autoZoomRevertTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    if lastAutoZoomRun == .ranEmpty {
                        lastAutoZoomRun = .idle
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 10))
                Text("Detect")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.purple.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.purple.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.purple.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!coordinator.canAutoZoom)
        .opacity(coordinator.canAutoZoom ? 1.0 : 0.4)
    }

    private enum ZoomFocusTag {
        case followCursor, center
    }

    private func zoomLevelBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { coordinator.project.zoomSegments.first { $0.id == id }?.zoomLevel ?? 1.5 },
            set: { coordinator.setZoomLevel(id: id, level: $0) }
        )
    }

    private func focusModeBinding(for id: UUID) -> Binding<ZoomFocusTag> {
        Binding(
            get: {
                guard let seg = coordinator.project.zoomSegments.first(where: { $0.id == id }) else { return .followCursor }
                if case .followCursor = seg.focusMode { return .followCursor }
                return .center
            },
            set: { tag in
                switch tag {
                case .followCursor: coordinator.setZoomFocusMode(id: id, mode: .followCursor)
                case .center: coordinator.setZoomFocusMode(id: id, mode: .manual(x: 0.5, y: 0.5))
                }
            }
        )
    }

    // MARK: - Reusable Components

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.leading, 2)
    }

    private var cardDivider: some View {
        Divider().background(Color.white.opacity(0.06))
    }

    private func settingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func settingToggleRow(_ label: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 36)
    }

    /// Vertical layout slider: label + value on top row, full-width slider below.
    /// This gives the slider track maximum width for easy dragging.
    private func verticalSliderRow(
        _ label: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String,
        precision: Int = 0,
        step: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if precision > 0 {
                    Text(String(format: "%.\(precision)f\(unit)", value.wrappedValue))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(Int(value.wrappedValue))\(unit)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func settingPickerRow<SelectionValue: Hashable, Content: View>(
        _ label: LocalizedStringKey,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            Picker("", selection: selection) {
                content()
            }
            .frame(width: 110)
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - NSColorPanel Bridge
//
// `NSColorPanel` is a long-lived singleton that notifies its observer via
// Objective-C target/action — it stays active across many user
// interactions (opening/closing the panel, dragging sliders) and survives
// SwiftUI view rebuilds. A plain closure capture doesn't survive those
// lifecycles, so we keep a single shared `NSObject` subclass that holds a
// weak reference to whichever `EditorCoordinator` should receive updates.
// The bridge is set fresh each time `openCustomColorPanel()` runs.
//
// `@objc` + `@MainActor` because `NSColorPanel`'s action is called on the
// main thread and `coordinator.project.backgroundStyle` is @MainActor state.

@MainActor
private final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()

    weak var coordinator: EditorCoordinator?

    @objc func colorPanelColorChanged(_ sender: NSColorPanel) {
        guard let coordinator else { return }
        let ns = sender.color.usingColorSpace(.sRGB) ?? sender.color
        coordinator.project.backgroundStyle.solidColor = CodableColor(
            red: Double(ns.redComponent),
            green: Double(ns.greenComponent),
            blue: Double(ns.blueComponent)
        )
    }
}
