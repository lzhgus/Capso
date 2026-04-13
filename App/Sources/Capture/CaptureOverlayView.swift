// App/Sources/Capture/CaptureOverlayView.swift
import AppKit
import CaptureKit

enum CaptureOverlayMode {
    case area
    case windowSelection([WindowInfo])
}

@MainActor
final class CaptureOverlayView: NSView {
    var onSelectionComplete: ((CGRect) -> Void)?
    var onWindowSelected: ((CGWindowID) -> Void)?
    var onCancel: (() -> Void)?

    private var mode: CaptureOverlayMode = .area
    private var isDragging = false
    private var dragStart: NSPoint = .zero
    private var dragEnd: NSPoint = .zero
    private var currentMouseLocation: NSPoint = .zero

    // Window selection state
    private var hoveredWindowID: CGWindowID?
    private var hoveredWindowFrame: CGRect = .zero
    private var hoveredWindowName: String = ""
    private var availableWindows: [WindowInfo] = []

    private var cursorHidden = false

    /// Pre-captured frozen screenshot. When set, drawn as the background
    /// instead of being transparent, preserving dropdown menus/popups.
    var frozenBackground: CGImage?

    // Overlay appearance
    private let overlayColor = NSColor.black.withAlphaComponent(0.3)
    private let selectionBorderColor = NSColor.white
    private let windowHighlightColor = NSColor.systemBlue.withAlphaComponent(0.3)
    private let windowBorderColor = NSColor.systemBlue
    private let dimensionFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    private let dimensionBgColor = NSColor.black.withAlphaComponent(0.7)
    private let dimensionTextColor = NSColor.white

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func resetSelection() {
        isDragging = false
        dragStart = .zero
        dragEnd = .zero
        hoveredWindowID = nil
        needsDisplay = true
        // Only hide cursor in area mode — we draw our own crosshair reticle.
        // In window selection mode, keep the normal cursor visible so
        // the user can see where they're pointing.
        if case .area = mode {
            if !cursorHidden {
                NSCursor.hide()
                cursorHidden = true
            }
        } else {
            restoreCursorIfNeeded()
        }
    }

    /// Restore cursor if hidden — safe to call multiple times
    func restoreCursorIfNeeded() {
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
    }

    private func restoreCursor() {
        restoreCursorIfNeeded()
    }

    func setMode(_ mode: CaptureOverlayMode) {
        self.mode = mode
        switch mode {
        case .windowSelection(let windows):
            self.availableWindows = windows
        case .area:
            self.availableWindows = []
        }
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        switch mode {
        case .area:
            drawAreaMode(in: context)
        case .windowSelection:
            drawWindowSelectionMode(in: context)
        }
    }

    private func drawAreaMode(in context: CGContext) {
        // The overlay is fully transparent. Nothing outside the selection
        // changes — no dark tint, no visual disruption. Only the selection
        // area gets a subtle white highlight to indicate what's being captured.

        if isDragging {
            let selectionRect = self.selectionRect

            // Selection border with shadow glow — visible on any background.
            // Dark shadow makes it clear on light backgrounds,
            // white border makes it clear on dark backgrounds.
            context.saveGState()
            context.setShadow(
                offset: .zero,
                blur: 10,
                color: NSColor.black.withAlphaComponent(0.5).cgColor
            )
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(1.5)
            context.stroke(selectionRect)
            context.restoreGState()

            drawDimensionLabel(for: selectionRect, in: context)
            drawReticle(at: currentMouseLocation, in: context)
        } else {
            // Before dragging: fully transparent, just crosshair
            drawReticle(at: currentMouseLocation, in: context)
            drawCoordinateLabel(at: currentMouseLocation, in: context)
        }
    }

    private func drawWindowSelectionMode(in context: CGContext) {
        // Fill entire screen with dim overlay
        context.setFillColor(overlayColor.cgColor)
        context.fill(bounds)

        // If a window is hovered, clear it and highlight with rounded corners
        if hoveredWindowID != nil {
            let viewRect = screenRectToViewRect(hoveredWindowFrame)
            let cornerRadius: CGFloat = 10 // macOS window corner radius

            let roundedPath = CGPath(roundedRect: viewRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

            // Clear the window area (rounded)
            context.setBlendMode(.clear)
            context.addPath(roundedPath)
            context.fillPath()
            context.setBlendMode(.normal)

            // Highlight border (rounded)
            context.setStrokeColor(windowBorderColor.cgColor)
            context.setLineWidth(3.0)
            context.addPath(roundedPath)
            context.strokePath()

            // Subtle fill (rounded)
            context.setFillColor(windowHighlightColor.cgColor)
            context.addPath(roundedPath)
            context.fillPath()

            // Window name label
            drawWindowLabel(name: hoveredWindowName, for: viewRect, in: context)
        }
    }

    private func drawWindowLabel(name: String, for rect: CGRect, in context: CGContext) {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dimensionTextColor
        ]
        let size = (name as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 8
        let labelWidth = size.width + padding * 2
        let labelHeight = size.height + padding

        // Position label centered above the window
        let labelX = rect.midX - labelWidth / 2
        let labelY = rect.maxY + 8

        let bgRect = CGRect(x: labelX, y: labelY, width: labelWidth, height: labelHeight)
        context.setFillColor(dimensionBgColor.cgColor)
        let path = CGPath(roundedRect: bgRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(path)
        context.fillPath()

        let textPoint = NSPoint(x: labelX + padding, y: labelY + (labelHeight - size.height) / 2)
        (name as NSString).draw(at: textPoint, withAttributes: attributes)
    }

    /// Convert screen coordinates (origin top-left) to view coordinates (origin bottom-left).
    private func screenRectToViewRect(_ screenRect: CGRect) -> CGRect {
        guard let screen = window?.screen else { return screenRect }
        let screenFrame = screen.frame
        // Screen coords: origin top-left. NSView coords: origin bottom-left.
        let viewY = screenFrame.height - screenRect.origin.y - screenRect.height
        return CGRect(
            x: screenRect.origin.x - screenFrame.origin.x,
            y: viewY,
            width: screenRect.width,
            height: screenRect.height
        )
    }

    private var selectionRect: CGRect {
        let x = min(dragStart.x, dragEnd.x)
        let y = min(dragStart.y, dragEnd.y)
        let w = abs(dragEnd.x - dragStart.x)
        let h = abs(dragEnd.y - dragStart.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func drawDimensionLabel(for rect: CGRect, in context: CGContext) {
        let text = "\(Int(rect.width)) x \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: dimensionFont,
            .foregroundColor: dimensionTextColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 6
        let labelWidth = size.width + padding * 2
        let labelHeight = size.height + padding

        let labelX = rect.midX - labelWidth / 2
        let labelY = rect.minY - labelHeight - 8

        let bgRect = CGRect(x: labelX, y: labelY, width: labelWidth, height: labelHeight)
        context.setFillColor(dimensionBgColor.cgColor)
        let path = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(path)
        context.fillPath()

        let textPoint = NSPoint(x: labelX + padding, y: labelY + (labelHeight - size.height) / 2)
        (text as NSString).draw(at: textPoint, withAttributes: attributes)
    }

    /// Draw a small crosshair reticle at the cursor position.
    /// Short arms (~18px) with a gap in the center — no full-screen lines.
    private func drawReticle(at point: NSPoint, in context: CGContext) {
        let armLength: CGFloat = 20
        let gap: CGFloat = 4

        // Draw each arm with dark outline + white fill for visibility on any background
        let arms: [(CGPoint, CGPoint)] = [
            (CGPoint(x: point.x, y: point.y + gap), CGPoint(x: point.x, y: point.y + gap + armLength)),
            (CGPoint(x: point.x, y: point.y - gap), CGPoint(x: point.x, y: point.y - gap - armLength)),
            (CGPoint(x: point.x + gap, y: point.y), CGPoint(x: point.x + gap + armLength, y: point.y)),
            (CGPoint(x: point.x - gap, y: point.y), CGPoint(x: point.x - gap - armLength, y: point.y)),
        ]

        // Dark outline (draw first, thicker)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(3.0)
        for (start, end) in arms {
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }

        // White fill (draw on top, thinner)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.5)
        for (start, end) in arms {
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }
    }

    /// Draw coordinate label near the cursor (before dragging starts).
    private func drawCoordinateLabel(at point: NSPoint, in context: CGContext) {
        let x = Int(point.x)
        let y = Int(bounds.height - point.y) // flip to screen coordinates
        let text = "\(x), \(y)"
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.8)
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 4
        let labelWidth = size.width + padding * 2
        let labelHeight = size.height + padding

        // Position to the bottom-right of the cursor
        let labelX = point.x + 24
        let labelY = point.y - labelHeight - 8

        // Background pill
        let bgRect = CGRect(x: labelX, y: labelY, width: labelWidth, height: labelHeight)
        context.setFillColor(dimensionBgColor.cgColor)
        let path = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(path)
        context.fillPath()

        // Text
        let textPoint = NSPoint(x: labelX + padding, y: labelY + (labelHeight - size.height) / 2)
        (text as NSString).draw(at: textPoint, withAttributes: attributes)
    }

    // MARK: - Window Hit Testing

    /// Find which window contains the given screen-coordinate point.
    private func windowUnderCursor(at screenPoint: CGPoint) -> WindowInfo? {
        // Windows are in z-order from front to back; return the first (topmost) match
        for window in availableWindows {
            if window.frame.contains(screenPoint) {
                return window
            }
        }
        return nil
    }

    /// Convert view point to screen coordinates (top-left origin).
    private func viewPointToScreenPoint(_ viewPoint: NSPoint) -> CGPoint {
        guard let screen = window?.screen else { return viewPoint }
        let screenFrame = screen.frame
        let screenX = viewPoint.x + screenFrame.origin.x
        let screenY = screenFrame.height - viewPoint.y // flip Y
        return CGPoint(x: screenX, y: screenY)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        switch mode {
        case .area:
            isDragging = true
            dragStart = convert(event.locationInWindow, from: nil)
            dragEnd = dragStart
            needsDisplay = true

        case .windowSelection:
            if let windowID = hoveredWindowID {
                restoreCursor()
                onWindowSelected?(windowID)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard case .area = mode else { return }
        dragEnd = convert(event.locationInWindow, from: nil)
        currentMouseLocation = dragEnd
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard case .area = mode else { return }
        dragEnd = convert(event.locationInWindow, from: nil)
        isDragging = false

        let rect = selectionRect
        if rect.width > 5 && rect.height > 5 {
            NSCursor.unhide()
            onSelectionComplete?(rect)
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        currentMouseLocation = convert(event.locationInWindow, from: nil)

        switch mode {
        case .area:
            break
        case .windowSelection:
            let screenPoint = viewPointToScreenPoint(currentMouseLocation)
            if let window = windowUnderCursor(at: screenPoint) {
                hoveredWindowID = window.id
                hoveredWindowFrame = window.frame
                hoveredWindowName = "\(window.appName) — \(window.title)"
            } else {
                hoveredWindowID = nil
            }
        }

        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            NSCursor.unhide()
            onCancel?()
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
