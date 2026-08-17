import AppKit
import SwiftUI

enum RecordingSelectionMode: CaseIterable, Equatable {
    case area
    case window
    case fullScreen
    case lastArea

    init?(keyCode: UInt16) {
        switch keyCode {
        case 0: self = .area
        case 13: self = .window
        case 3: self = .fullScreen
        case 15: self = .lastArea
        default: return nil
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .area: "Area"
        case .window: "Window"
        case .fullScreen: "Full Screen"
        case .lastArea: "Last Area"
        }
    }

    var shortcut: String {
        switch self {
        case .area: "A"
        case .window: "W"
        case .fullScreen: "F"
        case .lastArea: "R"
        }
    }

    var systemImage: String {
        switch self {
        case .area: "viewfinder"
        case .window: "macwindow"
        case .fullScreen: "rectangle.inset.filled"
        case .lastArea: "arrow.counterclockwise"
        }
    }
}

@MainActor
final class RecordingSelectionModeWindow: NSPanel {
    private let onSelect: (RecordingSelectionMode) -> Void
    private let onCancel: () -> Void
    private let canUseLastArea: Bool

    init(
        screen: NSScreen,
        selectedMode: RecordingSelectionMode,
        canUseLastArea: Bool,
        onSelect: @escaping (RecordingSelectionMode) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.canUseLastArea = canUseLastArea

        let size = NSSize(width: 520, height: 68)
        let visible = screen.visibleFrame
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 24,
            width: size.width,
            height: size.height
        )

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver + 1
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        contentView = NSHostingView(rootView: RecordingSelectionModeRail(
            selectedMode: selectedMode,
            canUseLastArea: canUseLastArea,
            onSelect: onSelect
        ))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show() {
        orderFrontRegardless()
        makeKey()
        makeFirstResponder(contentView)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
            return
        }
        if let mode = RecordingSelectionMode(keyCode: event.keyCode) {
            guard mode != .lastArea || canUseLastArea else {
                NSSound.beep()
                return
            }
            onSelect(mode)
            return
        }
        super.keyDown(with: event)
    }
}

private struct RecordingSelectionModeRail: View {
    let selectedMode: RecordingSelectionMode
    let canUseLastArea: Bool
    let onSelect: (RecordingSelectionMode) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RecordingSelectionMode.allCases, id: \.self) { mode in
                let isSelected = selectedMode == mode
                let foregroundColor: Color = isSelected ? .white : .primary
                let shortcutColor: Color = isSelected ? .white.opacity(0.72) : .secondary
                let backgroundColor: Color = isSelected ? .accentColor : .clear

                Button {
                    onSelect(mode)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                        Text(mode.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(mode.shortcut)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(shortcutColor)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(foregroundColor)
                    .background(
                        backgroundColor,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(RecordingModeButtonStyle())
                .disabled(mode == .lastArea && !canUseLastArea)
                .help(mode == .lastArea && !canUseLastArea ? "Record an area once to enable Last Area" : "")
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 18, y: 6)
        .padding(.horizontal, 2)
    }
}

private struct RecordingModeButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
