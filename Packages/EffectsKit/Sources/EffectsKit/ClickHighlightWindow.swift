// Packages/EffectsKit/Sources/EffectsKit/ClickHighlightWindow.swift
import AppKit
import QuartzCore

@MainActor
public final class ClickHighlightWindow: NSPanel {
    private let displayID: CGDirectDisplayID

    public init(displayID: CGDirectDisplayID) {
        self.displayID = displayID

        // Find the NSScreen matching this displayID
        let screens = NSScreen.screens
        let screen = screens.first { s in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            return (s.deviceDescription[key] as? CGDirectDisplayID) == displayID
        } ?? screens.first!
        let frame = screen.frame

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.sharingType = .none

        // Layer-backed content view for Core Animation
        let contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        self.contentView = contentView
    }

    /// Show a click highlight at the given point.
    /// `point` is in global CG screen coordinates (top-left origin of primary display).
    public func showClick(at point: CGPoint) {
        guard let contentView = self.contentView, let layer = contentView.layer else { return }

        let displayBounds = CGDisplayBounds(displayID)

        // Convert global CG coords to window-local NS coords
        // CG origin: top-left of primary display
        // NS origin: bottom-left of this screen
        let localX = point.x - displayBounds.origin.x
        let localY = displayBounds.size.height - (point.y - displayBounds.origin.y)

        let diameter: CGFloat = 40
        let circleRect = CGRect(
            x: localX - diameter / 2,
            y: localY - diameter / 2,
            width: diameter,
            height: diameter
        )

        let circle = CAShapeLayer()
        circle.path = CGPath(ellipseIn: CGRect(origin: .zero, size: circleRect.size), transform: nil)
        circle.fillColor = NSColor.systemBlue.withAlphaComponent(0.35).cgColor
        circle.frame = circleRect

        layer.addSublayer(circle)

        // Scale animation: 1.0 → 2.0
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 1.0
        scaleAnim.toValue = 2.0

        // Opacity animation: 1.0 → 0.0
        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 1.0
        opacityAnim.toValue = 0.0

        let group = CAAnimationGroup()
        group.animations = [scaleAnim, opacityAnim]
        group.duration = 0.3
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            circle.removeFromSuperlayer()
        }
        circle.add(group, forKey: "clickPulse")
        CATransaction.commit()
    }

    public func showWindow() {
        self.orderFrontRegardless()
    }

    public func hideWindow() {
        self.orderOut(nil)
    }
}
