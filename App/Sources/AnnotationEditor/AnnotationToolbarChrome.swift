import SwiftUI
import AnnotationKit

enum AnnotationToolbarChrome {
    static func buttonBackground(
        isActive: Bool = false,
        isPrimary: Bool = false,
        isEnabled: Bool = true
    ) -> Color {
        if !isEnabled { return Color.white.opacity(0.06) }
        if isPrimary { return Color.accentColor.opacity(0.82) }
        if isActive { return Color.accentColor.opacity(0.45) }
        return Color.white.opacity(0.10)
    }

    static func sizeRange(for tool: AnnotationTool, isFontSizeMode: Bool) -> ClosedRange<CGFloat> {
        if isFontSizeMode { return 12...120 }
        switch tool {
        case .pixelate: return 4...48
        case .counter: return 12...40
        case .highlighter: return 10...100
        default: return 1...40
        }
    }

    static func sizeStep(for tool: AnnotationTool, isFontSizeMode: Bool) -> CGFloat {
        if isFontSizeMode { return 1 }
        switch tool {
        case .pixelate, .highlighter: return 2
        default: return 1
        }
    }

    static func sizeHelp(for tool: AnnotationTool, isFontSizeMode: Bool, value: CGFloat) -> String {
        let title: String
        if isFontSizeMode {
            title = String(localized: "Font Size")
        } else {
            switch tool {
            case .pixelate: title = String(localized: "Block Size")
            case .counter: title = String(localized: "Counter Size")
            case .highlighter: title = String(localized: "Highlighter Width")
            default: title = String(localized: "Line Width")
            }
        }
        return "\(title): \(Int(value))"
    }

    static func showsFillToggle(for tool: AnnotationTool, isFontSizeMode: Bool) -> Bool {
        switch tool {
        case .counter, .arrow, .line, .highlighter, .pixelate:
            return false
        default:
            return !isFontSizeMode
        }
    }
}

extension AnnotationTool {
    var toolbarIconName: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .freehand: return "pencil.tip"
        case .pixelate: return "eye.slash.fill"
        case .counter: return "number.circle.fill"
        case .highlighter: return "highlighter"
        case .spotlight: return "flashlight.on.fill"
        }
    }

    var toolbarHoverLabel: String {
        switch self {
        case .select: return String(localized: "Select")
        case .arrow: return String(localized: "Arrow")
        case .line: return String(localized: "Line")
        case .rectangle: return String(localized: "Rect")
        case .ellipse: return String(localized: "Oval")
        case .text: return String(localized: "Text")
        case .freehand: return String(localized: "Draw")
        case .pixelate: return String(localized: "Pixel")
        case .counter: return String(localized: "Count")
        case .highlighter: return String(localized: "Mark")
        case .spotlight: return String(localized: "Spotlight")
        }
    }
}

extension View {
    func annotationToolbarSurface() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
            )
            .environment(\.colorScheme, .dark)
    }
}

struct AnnotationToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(width: 1, height: 30)
    }
}

/// "Aa" stands in for the text tool: the `textformat` symbol is localized per language.
struct AnnotationToolGlyph: View {
    let tool: AnnotationTool

    var body: some View {
        if tool == .text {
            Text(verbatim: "Aa")
                .font(.system(size: 13, weight: .semibold))
        } else {
            Image(systemName: tool.toolbarIconName)
                .font(.system(size: 14, weight: .medium))
        }
    }
}

private struct AnnotationToolbarHoverLabel<Icon: View>: View {
    let label: String
    let isHovered: Bool
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        VStack(spacing: isHovered ? 1 : 0) {
            icon()
                .frame(height: isHovered ? 17 : 38)

            if isHovered {
                Text(label)
                    .font(.system(size: 8.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
    }
}

struct AnnotationToolbarToolButton: View {
    let tool: AnnotationTool
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            AnnotationToolbarHoverLabel(label: tool.toolbarHoverLabel, isHovered: isHovered) {
                AnnotationToolGlyph(tool: tool)
            }
            .frame(width: 29, height: 38)
            .background(isActive ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.001))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tool.localizedShortcutHelpTitle)
    }
}

struct AnnotationToolbarIconFace: View {
    let systemName: String
    var isActive = false
    var isPrimary = false
    var isEnabled = true

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 28)
            .background(AnnotationToolbarChrome.buttonBackground(
                isActive: isActive,
                isPrimary: isPrimary,
                isEnabled: isEnabled
            ))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(isEnabled ? 1 : 0.35)
    }
}

struct AnnotationToolbarIconButton: View {
    let systemName: String
    let help: LocalizedStringKey
    var isActive = false
    var isPrimary = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AnnotationToolbarIconFace(
                systemName: systemName,
                isActive: isActive,
                isPrimary: isPrimary,
                isEnabled: isEnabled
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
    }
}

struct AnnotationToolbarSegmentedControl<Option: Hashable, Label: View>: View {
    let options: [Option]
    @Binding var selection: Option
    let itemWidth: CGFloat
    let help: LocalizedStringKey
    let itemHelp: (Option) -> Text
    @ViewBuilder let label: (Option) -> Label

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    label(option)
                        .foregroundStyle(.white)
                        .frame(width: itemWidth, height: 26)
                        .background(selection == option ? Color.accentColor.opacity(0.48) : Color.white.opacity(0.001))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(itemHelp(option))
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(help)
    }
}

struct AnnotationToolbarRedactionModeControl: View {
    @Binding var selection: RedactionMode

    var body: some View {
        AnnotationToolbarSegmentedControl(
            options: RedactionMode.allCases,
            selection: $selection,
            itemWidth: 48,
            help: "Redaction Mode",
            itemHelp: { Text($0.label) }
        ) { mode in
            Text(mode.label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

struct AnnotationToolbarStrokePatternControl: View {
    @Binding var selection: StrokePattern

    var body: some View {
        AnnotationToolbarSegmentedControl(
            options: StrokePattern.allCases,
            selection: $selection,
            itemWidth: 30,
            help: "Stroke Pattern",
            itemHelp: { Text($0.rawValue.capitalized) }
        ) { pattern in
            StrokePatternGlyph(pattern: pattern)
        }
    }
}

struct AnnotationToolbarTextEffects: View {
    @Binding var fill: Bool
    @Binding var outline: Bool
    @Binding var trace: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextEffectButton(label: String(localized: "Fill"), help: "Text Fill", isOn: $fill) {
                Image(systemName: "square.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            TextEffectButton(label: String(localized: "Box"), help: "Text Box Outline", isOn: $outline) {
                Image(systemName: "square")
                    .font(.system(size: 13, weight: .semibold))
            }
            TextEffectButton(label: String(localized: "Trace"), help: "Text Trace", isOn: $trace) {
                Text(verbatim: "Aa")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
    }

    private struct TextEffectButton<Icon: View>: View {
        let label: String
        let help: LocalizedStringKey
        @Binding var isOn: Bool
        @ViewBuilder let icon: () -> Icon

        @State private var isHovered = false

        var body: some View {
            Button {
                isOn.toggle()
            } label: {
                AnnotationToolbarHoverLabel(label: label, isHovered: isHovered, icon: icon)
                    .frame(width: 32, height: 38)
                    .background(AnnotationToolbarChrome.buttonBackground(isActive: isOn))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help(help)
        }
    }
}
