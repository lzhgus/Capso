// App/Sources/OCR/ToastWindow.swift
import AppKit
import SwiftUI

/// A reusable Liquid Glass toast notification that slides up from bottom-center.
@MainActor
final class ToastWindow: NSPanel {
    private var dismissTimer: Timer?

    init(message: String, icon: String = "checkmark.circle.fill", iconColor: NSColor = .systemGreen, screen: NSScreen? = nil) {
        // The hosting view sizes the panel to its content, so center on that size.
        let hostingView = NSHostingView(rootView: ToastView(message: message, icon: icon, iconColor: Color(nsColor: iconColor)))
        let windowWidth = hostingView.fittingSize.width
        let windowHeight = hostingView.fittingSize.height

        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = targetScreen.visibleFrame
        let x = screenFrame.midX - windowWidth / 2
        let y = screenFrame.minY + 50

        super.init(
            contentRect: NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.isMovableByWindowBackground = false
        self.animationBehavior = .utilityWindow

        self.contentView = hostingView
    }

    func show(autoDismissAfter: TimeInterval = 1.5) {
        let finalFrame = frame
        var startFrame = finalFrame
        startFrame.origin.y -= 20
        setFrame(startFrame, display: false)
        alphaValue = 0

        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(finalFrame, display: true)
            self.animator().alphaValue = 1
        }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: autoDismissAfter, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    private func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}

private struct ToastView: View {
    let message: String
    let icon: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .fixedSize()
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .padding(12)
    }
}
