// App/Sources/Capture/SelfTimerHUD.swift
import AppKit
import SwiftUI
import SharedKit

/// Floating countdown overlay shown during a Self-Timer capture.
///
/// Visual design (see docs / design spec): rounded-square HUD using
/// `.regularMaterial` vibrancy, monochrome progress ring draining clockwise,
/// SF Rounded numeric digit driven by `.contentTransition(.numericText)`.
/// Adapts to light / dark with the system; never branded with accent color.
@MainActor
final class SelfTimerHUD {
    private var panel: SelfTimerPanel?
    private var borderPanel: NSPanel?
    private let viewModel = SelfTimerViewModel()
    private var keyMonitor: Any?
    private var positionPersist: ((CGPoint) -> Void)?
    private var onCancel: (() -> Void)?
    private var playTickSound: Bool = false

    /// Reusable system "Tink" sound for per-second countdown ticks. Loaded
    /// once and stopped/restarted on each tick so consecutive ticks don't
    /// drop. The shutter sound at t=0 is fired by `CaptureCoordinator`, not
    /// here — we never tick on the final beat.
    private static let tickSound: NSSound? = NSSound(named: "Tink")

    /// Show the HUD on `screen` for `duration` seconds. Draws a thin
    /// monochrome border around `selectionRect` for the lifetime of the
    /// countdown so the user can see what's about to be captured. Calls
    /// `onComplete` once the countdown finishes — the caller is expected
    /// to immediately fire the capture. Calls `onCancel` on Esc / click.
    /// Both the HUD and the border are guaranteed to be off-screen
    /// *before* `onComplete` returns.
    func show(
        on screen: NSScreen,
        selectionRect: CGRect,
        duration: Int,
        playTickSound: Bool,
        savedPosition: CGPoint?,
        persistPosition: @escaping (CGPoint) -> Void,
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss()  // guard against re-entrant show

        self.positionPersist = persistPosition
        self.onCancel = onCancel
        self.playTickSound = playTickSound
        viewModel.totalDuration = TimeInterval(duration)
        viewModel.startDate = Date()
        viewModel.remaining = duration

        showSelectionBorder(rect: selectionRect, screen: screen)

        let size = NSSize(width: 108, height: 108)
        let origin = Self.resolveOrigin(savedPosition: savedPosition, screen: screen, hudSize: size)

        let panel = SelfTimerPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // SwiftUI draws its own
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true

        let host = NSHostingView(rootView: SelfTimerHUDView(
            viewModel: viewModel,
            hudSize: size,
            onCancel: { [weak self] in self?.cancelByUser() },
            onDragEnded: { [weak self] newOrigin in
                self?.positionPersist?(newOrigin)
            }
        ))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        self.panel = panel

        installKeyMonitor()

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        // Drive the visible digit on a 1Hz tick. The progress ring is driven
        // by TimelineView in SwiftUI for sub-second smoothness.
        Task { [weak self] in
            guard let self else { return }
            for tick in 1...duration {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled || self.panel == nil { return }
                let next = duration - tick
                withAnimation(.snappy(duration: 0.28)) {
                    self.viewModel.remaining = next
                }
                // Tick on every beat *except* the final one — at t=0 the
                // shutter sound from CaptureCoordinator takes over.
                if next > 0 && self.playTickSound {
                    Self.tickSound?.stop()
                    Self.tickSound?.play()
                }
            }
            // Tear down both panels synchronously, give the window server
            // two frames to ensure they're fully off-screen, then fire.
            self.dismissImmediate()
            try? await Task.sleep(for: .milliseconds(33))
            onComplete()
        }
    }

    /// Draw a 2pt white border around `rect` on `screen`, with a soft black
    /// outer shadow so the border stays visible on any wallpaper. Sits at
    /// `.floating` level just below the HUD; ignores mouse events so the
    /// user can keep interacting with whatever they're capturing.
    private func showSelectionBorder(rect: CGRect, screen: NSScreen) {
        let inset: CGFloat = 4  // padding around the rect for the stroke + shadow
        let screenOrigin = screen.frame.origin
        let panelRect = NSRect(
            x: screenOrigin.x + rect.origin.x - inset,
            y: screenOrigin.y + rect.origin.y - inset,
            width: rect.width + inset * 2,
            height: rect.height + inset * 2
        )
        let panel = NSPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false

        let view = SelfTimerBorderView(
            frame: NSRect(origin: .zero, size: panelRect.size),
            inset: inset
        )
        panel.contentView = view
        self.borderPanel = panel
        panel.orderFrontRegardless()
    }

    /// User-driven cancel (Esc / click). Animates out then calls onCancel.
    private func cancelByUser() {
        let cb = onCancel
        animatedDismiss { cb?() }
    }

    /// Pull both panels down with no animation. Used when the timer fires —
    /// the screenshot must not see either panel, so this is synchronous.
    private func dismissImmediate() {
        if let mon = keyMonitor {
            NSEvent.removeMonitor(mon)
            keyMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        borderPanel?.orderOut(nil)
        borderPanel = nil
    }

    /// Animate then tear down. Used for cancel paths. Uses a delayed
    /// `asyncAfter` for clean-up rather than `runAnimationGroup`'s
    /// completion handler — that closure is `@Sendable`, which doesn't play
    /// nicely with main-actor-isolated state. The pattern matches
    /// `CaptureCoordinator.dismissOverlay`.
    private func animatedDismiss(then completion: (() -> Void)? = nil) {
        guard let panel else { completion?(); return }
        if let mon = keyMonitor {
            NSEvent.removeMonitor(mon)
            keyMonitor = nil
        }
        let border = borderPanel
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
            border?.animator().alphaValue = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            panel.orderOut(nil)
            border?.orderOut(nil)
            self?.panel = nil
            self?.borderPanel = nil
            completion?()
        }
    }

    /// External cancel (e.g., another capture flow starts). No callback fires.
    func dismiss() {
        if let mon = keyMonitor {
            NSEvent.removeMonitor(mon)
            keyMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        borderPanel?.orderOut(nil)
        borderPanel = nil
        onCancel = nil
        positionPersist = nil
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.cancelByUser()
                return nil
            }
            return event
        }
    }

    /// Default placement: top-center of `screen`, 80pt below the menu bar /
    /// top edge. If the user has dragged before, restore that position
    /// clamped into the visible frame so a disconnected display can't trap
    /// the HUD off-screen.
    private static func resolveOrigin(savedPosition: CGPoint?, screen: NSScreen, hudSize: NSSize) -> NSPoint {
        if let saved = savedPosition {
            let visible = screensVisibleBounds()
            let x = max(visible.minX, min(saved.x, visible.maxX - hudSize.width))
            let y = max(visible.minY, min(saved.y, visible.maxY - hudSize.height))
            return NSPoint(x: x, y: y)
        }
        let frame = screen.visibleFrame
        let x = frame.midX - hudSize.width / 2
        let y = frame.maxY - hudSize.height - 80
        return NSPoint(x: x, y: y)
    }

    private static func screensVisibleBounds() -> NSRect {
        var union = NSRect.zero
        for s in NSScreen.screens {
            union = union.isEmpty ? s.visibleFrame : union.union(s.visibleFrame)
        }
        return union
    }
}

// MARK: - Panel (allows borderless windows to become key for Esc handling)

private final class SelfTimerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Selection border view

/// Draws a 2pt white border with a soft black outer shadow so the rect is
/// visible on bright, dark, and busy backgrounds alike. Static — no marching
/// ants — to keep the visual language quiet and consistent with the HUD.
private final class SelfTimerBorderView: NSView {
    private let inset: CGFloat

    init(frame: NSRect, inset: CGFloat) {
        self.inset = inset
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: inset, dy: inset)

        ctx.saveGState()
        ctx.setShadow(
            offset: .zero,
            blur: 4,
            color: NSColor.black.withAlphaComponent(0.5).cgColor
        )
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(rect)
        ctx.restoreGState()
    }
}

// MARK: - View model

@MainActor
@Observable
final class SelfTimerViewModel {
    var totalDuration: TimeInterval = 5
    var startDate: Date = Date()
    var remaining: Int = 5
}

// MARK: - SwiftUI view

private struct SelfTimerHUDView: View {
    let viewModel: SelfTimerViewModel
    let hudSize: NSSize
    let onCancel: () -> Void
    /// Called when a drag finishes, with the new bottom-left origin in screen
    /// coordinates (matching NSWindow.frame.origin convention).
    let onDragEnded: (CGPoint) -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack {
            // Backdrop: rounded square with vibrancy + thin inner edge.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: 8)

            // Progress ring + digit.
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(viewModel.startDate)
                let progress = max(0, min(1, 1 - elapsed / viewModel.totalDuration))

                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 3)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color.primary.opacity(0.85),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))

                    Group {
                        if isHovering {
                            Image(systemName: "xmark")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.primary.opacity(0.6))
                        } else {
                            Text("\(viewModel.remaining)")
                                .font(.system(size: 44, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText(countsDown: true))
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .frame(width: hudSize.width, height: hudSize.height)
        .overlay(WindowDragHandle(onTap: onCancel, onDragEnded: onDragEnded))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Self-timer countdown"))
        .accessibilityValue(Text("\(viewModel.remaining) seconds remaining"))
    }
}
