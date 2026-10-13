import AppKit
import SwiftUI

/// Non-modal banner shown next to the recording controls. Hidden from the capture.
@MainActor
final class RecordingWarningPanel: NSPanel {
    struct Action {
        let title: String
        let isProminent: Bool
        let perform: () -> Void
    }

    init(message: String, actions: [Action], above anchor: NSRect, screen: NSScreen) {
        let width: CGFloat = 340
        let view = RecordingWarningView(message: message, actions: actions)
        let hosting = NSHostingView(rootView: view)
        let height = hosting.fittingSize.height

        let visible = screen.visibleFrame
        let x = max(visible.minX + 8, min(anchor.midX - width / 2, visible.maxX - width - 8))
        var y = anchor.maxY + 8
        if y + height > visible.maxY - 8 { y = anchor.minY - height - 8 }

        super.init(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .transient]
        sharingType = .none
        contentView = hosting
    }

    func show() { orderFrontRegardless() }
}

private struct RecordingWarningView: View {
    let message: String
    let actions: [RecordingWarningPanel.Action]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                ForEach(actions.indices, id: \.self) { index in
                    let action = actions[index]
                    Button(action.title, action: action.perform)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: action.isProminent ? .semibold : .regular))
                        .foregroundStyle(action.isProminent ? .red : .white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(.black.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
