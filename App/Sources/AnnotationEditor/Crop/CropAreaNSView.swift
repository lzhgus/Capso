// App/Sources/AnnotationEditor/Crop/CropAreaNSView.swift
import AppKit
import AnnotationKit

final class CropAreaNSView: NSView {
    var cropRect: CGRect = .zero { didSet { needsDisplay = true } }
    var imageSize: CGSize = .zero
    var zoomScale: CGFloat = 1.0 { didSet { needsDisplay = true } }
    /// Aspect ratio (width/height) to enforce during resize; nil for freeform.
    var aspectRatio: CGFloat?
    /// When true, snap to image edges unless ⌘ is held during the event.
    var snapEnabled: Bool = true
    /// Called whenever cropRect changes due to user interaction.
    var onCropRectChanged: ((CGRect) -> Void)?
    /// Called once when a drag/resize gesture ends, with the rect value at
    /// the moment before this drag began. Used by the editor to push a
    /// discrete undo entry per gesture (rather than per mouseDragged tick).
    var onDragEnded: ((CGRect) -> Void)?

    private enum ActiveHandle {
        case topLeft, top, topRight
        case left, right
        case bottomLeft, bottom, bottomRight
        case move
    }

    private var activeHandle: ActiveHandle?
    private var dragStartImagePoint: CGPoint?
    private var dragStartRect: CGRect?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let viewRect = viewRectForCrop()

        drawDimMask(ctx: ctx, cropViewRect: viewRect)
        drawRuleOfThirds(ctx: ctx, cropViewRect: viewRect)
        drawBorder(ctx: ctx, cropViewRect: viewRect)
        drawHandles(ctx: ctx, cropViewRect: viewRect)
        if activeHandle != nil {
            drawDimensionBadge(ctx: ctx, cropViewRect: viewRect)
        }
    }

    private func drawDimensionBadge(ctx: CGContext, cropViewRect: CGRect) {
        let text = "\(Int(cropRect.width)) × \(Int(cropRect.height))"
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let hPad: CGFloat = 7
        let vPad: CGFloat = 3
        let badgeW = textSize.width + hPad * 2
        let badgeH = textSize.height + vPad * 2

        // Prefer below the crop; fall back to above if too close to the bottom.
        let gap: CGFloat = 6
        let belowY = cropViewRect.maxY + gap
        let aboveY = cropViewRect.minY - gap - badgeH
        let badgeY = (belowY + badgeH <= bounds.maxY) ? belowY : max(aboveY, 2)

        var badgeX = cropViewRect.midX - badgeW / 2
        badgeX = max(2, min(badgeX, bounds.maxX - badgeW - 2))

        let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)

        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.78))
        let path = CGPath(roundedRect: badgeRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        let textPoint = NSPoint(x: badgeX + hPad, y: badgeY + vPad)
        (text as NSString).draw(at: textPoint, withAttributes: attrs)
    }

    private func drawDimMask(ctx: CGContext, cropViewRect: CGRect) {
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.45))
        ctx.fill(bounds)
        ctx.setBlendMode(.clear)
        ctx.fill(cropViewRect)
        ctx.restoreGState()
    }

    private func drawRuleOfThirds(ctx: CGContext, cropViewRect: CGRect) {
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.35))
        ctx.setLineWidth(0.5)
        let third = cropViewRect.width / 3
        let thirdY = cropViewRect.height / 3
        for i in 1...2 {
            let x = cropViewRect.minX + CGFloat(i) * third
            ctx.move(to: CGPoint(x: x, y: cropViewRect.minY))
            ctx.addLine(to: CGPoint(x: x, y: cropViewRect.maxY))
            let y = cropViewRect.minY + CGFloat(i) * thirdY
            ctx.move(to: CGPoint(x: cropViewRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: cropViewRect.maxX, y: y))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawBorder(ctx: CGContext, cropViewRect: CGRect) {
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        ctx.setLineWidth(1.0)
        ctx.stroke(cropViewRect)
        ctx.restoreGState()
    }

    private func drawHandles(ctx: CGContext, cropViewRect: CGRect) {
        let bracket: CGFloat = 18
        let thickness: CGFloat = 3
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1.0))
        ctx.setLineWidth(thickness)
        ctx.setLineCap(.square)

        let r = cropViewRect
        // Corners: two lines forming an L, pointing outward
        // Top-left
        ctx.move(to: CGPoint(x: r.minX, y: r.minY + bracket)); ctx.addLine(to: CGPoint(x: r.minX, y: r.minY))
        ctx.addLine(to: CGPoint(x: r.minX + bracket, y: r.minY))
        // Top-right
        ctx.move(to: CGPoint(x: r.maxX - bracket, y: r.minY)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY + bracket))
        // Bottom-right
        ctx.move(to: CGPoint(x: r.maxX, y: r.maxY - bracket)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        ctx.addLine(to: CGPoint(x: r.maxX - bracket, y: r.maxY))
        // Bottom-left
        ctx.move(to: CGPoint(x: r.minX + bracket, y: r.maxY)); ctx.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        ctx.addLine(to: CGPoint(x: r.minX, y: r.maxY - bracket))

        // Edge midpoints: short perpendicular dash
        let edge: CGFloat = 22
        ctx.move(to: CGPoint(x: r.midX - edge / 2, y: r.minY)); ctx.addLine(to: CGPoint(x: r.midX + edge / 2, y: r.minY))
        ctx.move(to: CGPoint(x: r.midX - edge / 2, y: r.maxY)); ctx.addLine(to: CGPoint(x: r.midX + edge / 2, y: r.maxY))
        ctx.move(to: CGPoint(x: r.minX, y: r.midY - edge / 2)); ctx.addLine(to: CGPoint(x: r.minX, y: r.midY + edge / 2))
        ctx.move(to: CGPoint(x: r.maxX, y: r.midY - edge / 2)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.midY + edge / 2))

        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Coordinate conversion

    private func viewRectForCrop() -> CGRect {
        CGRect(
            x: cropRect.minX * zoomScale,
            y: cropRect.minY * zoomScale,
            width: cropRect.width * zoomScale,
            height: cropRect.height * zoomScale
        )
    }

    private func imagePoint(from viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: viewPoint.x / zoomScale, y: viewPoint.y / zoomScale)
    }

    // MARK: - Hit testing

    private func handle(at viewPoint: CGPoint) -> ActiveHandle? {
        let r = viewRectForCrop()
        let hit: CGFloat = 14  // half-side of the handle hit square
        func near(_ a: CGPoint, _ b: CGPoint) -> Bool {
            abs(a.x - b.x) <= hit && abs(a.y - b.y) <= hit
        }
        if near(viewPoint, CGPoint(x: r.minX, y: r.minY)) { return .topLeft }
        if near(viewPoint, CGPoint(x: r.maxX, y: r.minY)) { return .topRight }
        if near(viewPoint, CGPoint(x: r.minX, y: r.maxY)) { return .bottomLeft }
        if near(viewPoint, CGPoint(x: r.maxX, y: r.maxY)) { return .bottomRight }
        if near(viewPoint, CGPoint(x: r.midX, y: r.minY)) { return .top }
        if near(viewPoint, CGPoint(x: r.midX, y: r.maxY)) { return .bottom }
        if near(viewPoint, CGPoint(x: r.minX, y: r.midY)) { return .left }
        if near(viewPoint, CGPoint(x: r.maxX, y: r.midY)) { return .right }
        if r.contains(viewPoint) { return .move }
        return nil
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)
        activeHandle = handle(at: viewPoint)
        dragStartImagePoint = imagePoint(from: viewPoint)
        dragStartRect = cropRect
    }

    override func mouseDragged(with event: NSEvent) {
        guard let handle = activeHandle,
              let startPoint = dragStartImagePoint,
              let startRect = dragStartRect else { return }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let currentPoint = imagePoint(from: viewPoint)
        let dx = currentPoint.x - startPoint.x
        let dy = currentPoint.y - startPoint.y
        let softSnap = snapEnabled && !event.modifierFlags.contains(.command)

        let newRect: CGRect
        switch handle {
        case .move:
            newRect = moveRect(startRect, by: CGSize(width: dx, height: dy))
        case .topLeft, .top, .topRight, .left, .right, .bottomLeft, .bottom, .bottomRight:
            newRect = resizeRect(startRect, handle: handle, dx: dx, dy: dy)
        }

        let snapped = softSnap
            ? CropSnap.snapRect(newRect, to: imageSize, threshold: 6 / zoomScale)
            : newRect
        let clamped = clampToImage(snapped)
        cropRect = clamped
        onCropRectChanged?(clamped)
    }

    override func mouseUp(with event: NSEvent) {
        // Emit the starting rect so the controller can record an undo entry
        // that reverses this gesture (not the per-tick intermediate states).
        if let startRect = dragStartRect, activeHandle != nil, startRect != cropRect {
            onDragEnded?(startRect)
        }
        activeHandle = nil
        dragStartImagePoint = nil
        dragStartRect = nil
    }

    // MARK: - Rect math

    private func moveRect(_ rect: CGRect, by delta: CGSize) -> CGRect {
        var r = rect.offsetBy(dx: delta.width, dy: delta.height)
        if r.minX < 0 { r.origin.x = 0 }
        if r.minY < 0 { r.origin.y = 0 }
        if r.maxX > imageSize.width { r.origin.x = imageSize.width - r.width }
        if r.maxY > imageSize.height { r.origin.y = imageSize.height - r.height }
        return r
    }

    private func resizeRect(_ start: CGRect, handle: ActiveHandle, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = start.minX
        var minY = start.minY
        var maxX = start.maxX
        var maxY = start.maxY

        switch handle {
        case .topLeft: minX += dx; minY += dy
        case .top: minY += dy
        case .topRight: maxX += dx; minY += dy
        case .left: minX += dx
        case .right: maxX += dx
        case .bottomLeft: minX += dx; maxY += dy
        case .bottom: maxY += dy
        case .bottomRight: maxX += dx; maxY += dy
        case .move: break
        }

        // Prevent inverted rects
        if minX > maxX { swap(&minX, &maxX) }
        if minY > maxY { swap(&minY, &maxY) }

        var result = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        if let ratio = aspectRatio {
            result = enforceRatio(result, handle: handle, anchor: anchor(for: handle, on: start), ratio: ratio)
        }

        return result
    }

    private func anchor(for handle: ActiveHandle, on rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.maxX, y: rect.midY)
        case .right: return CGPoint(x: rect.minX, y: rect.midY)
        case .bottomLeft: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomRight: return CGPoint(x: rect.minX, y: rect.minY)
        case .move: return CGPoint(x: rect.midX, y: rect.midY)
        }
    }

    private func enforceRatio(_ rect: CGRect, handle: ActiveHandle, anchor: CGPoint, ratio: CGFloat) -> CGRect {
        let w = rect.width
        let h = rect.height

        let newW: CGFloat
        let newH: CGFloat

        switch handle {
        case .left, .right:
            // Horizontal edge drag: width is user intent, derive height.
            newW = w
            newH = w / ratio
        case .top, .bottom:
            // Vertical edge drag: height is user intent, derive width.
            newH = h
            newW = h * ratio
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            // Corner drag: pick dominant axis by which dimension drifted most from ratio.
            let derivedWFromH = h * ratio
            let derivedHFromW = w / ratio
            let useWidth = abs(w - derivedWFromH) > abs(h - derivedHFromW)
            newW = useWidth ? w : derivedWFromH
            newH = useWidth ? derivedHFromW : h
        case .move:
            return rect
        }

        // Anchor at the fixed corner/edge
        let originX: CGFloat
        if abs(anchor.x - rect.maxX) < 1 { originX = anchor.x - newW }
        else if abs(anchor.x - rect.minX) < 1 { originX = anchor.x }
        else { originX = anchor.x - newW / 2 }

        let originY: CGFloat
        if abs(anchor.y - rect.maxY) < 1 { originY = anchor.y - newH }
        else if abs(anchor.y - rect.minY) < 1 { originY = anchor.y }
        else { originY = anchor.y - newH / 2 }

        return CGRect(x: originX, y: originY, width: newW, height: newH)
    }

    private func clampToImage(_ rect: CGRect) -> CGRect {
        let rawMinX = max(0, rect.minX)
        let rawMinY = max(0, rect.minY)
        let rawMaxX = min(imageSize.width, rect.maxX)
        let rawMaxY = min(imageSize.height, rect.maxY)
        let w = max(10, rawMaxX - rawMinX)
        let h = max(10, rawMaxY - rawMinY)
        // Pull the origin back so minimum size never overflows the image.
        let minX = max(0, min(rawMinX, imageSize.width - w))
        let minY = max(0, min(rawMinY, imageSize.height - h))
        return CGRect(x: minX, y: minY, width: w, height: h)
    }
}
