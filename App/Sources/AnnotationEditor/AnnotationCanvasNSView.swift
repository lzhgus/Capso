// App/Sources/AnnotationEditor/AnnotationCanvasNSView.swift
import AppKit
import CoreGraphics
import AnnotationKit

/// Which corner handle is being dragged for resize
private enum ResizeHandle {
    case topLeft, topRight, bottomLeft, bottomRight
}

@MainActor
final class AnnotationCanvasNSView: NSView {
    var document: AnnotationDocument?
    var sourceImage: CGImage?
    var currentTool: AnnotationTool = .select
    var currentStyle: StrokeStyle = StrokeStyle()
    var onDocumentChanged: (() -> Void)?
    var onObjectCreated: (() -> Void)?

    var zoomScale: CGFloat = 1.0

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var isDragging = false
    private var dragObjectID: ObjectID?
    private var activeResizeHandle: ResizeHandle?
    private var resizeOriginalBounds: CGRect?
    /// Original fontSize captured when a TextObject resize drag begins.
    /// Text uses intrinsic sizing (bounds derived from fontSize), so we scale
    /// fontSize from this original value — not the live one, which drifts each tick.
    private var resizeOriginalTextFontSize: CGFloat?
    private var activeFreehand: FreehandObject?

    private let handleRadius: CGFloat = 5  // in image coords (adjusted by zoom in drawing)

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // Ensure we become first responder when added to a window so that
    // keyDown events (e.g. Delete to remove selected annotation) are delivered.
    // Without this, the NSView hosted inside SwiftUI's NSHostingView never
    // receives key events and the system just beeps.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    private func toImagePoint(_ viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: viewPoint.x / zoomScale, y: viewPoint.y / zoomScale)
    }

    private func nextCounterNumber() -> Int {
        guard let doc = document else { return 1 }
        let maxNumber = doc.objects
            .compactMap { ($0 as? CounterObject)?.number }
            .max() ?? 0
        return maxNumber + 1
    }

    // MARK: - Handle Hit Testing

    private func handleHitTest(point: CGPoint, bounds: CGRect) -> ResizeHandle? {
        let r = handleRadius + 3  // generous hit area
        let corners: [(ResizeHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: bounds.minX, y: bounds.minY)),
            (.topRight, CGPoint(x: bounds.maxX, y: bounds.minY)),
            (.bottomLeft, CGPoint(x: bounds.minX, y: bounds.maxY)),
            (.bottomRight, CGPoint(x: bounds.maxX, y: bounds.maxY)),
        ]
        for (handle, corner) in corners {
            if hypot(point.x - corner.x, point.y - corner.y) <= r {
                return handle
            }
        }
        return nil
    }

    // MARK: - Cursor Management

    override func mouseMoved(with event: NSEvent) {
        guard currentTool == .select else {
            NSCursor.crosshair.set()
            return
        }

        let point = toImagePoint(convert(event.locationInWindow, from: nil))
        guard let doc = document else { return }

        // Check if over a handle of the selected object
        if let selected = doc.selectedObject {
            if let handle = handleHitTest(point: point, bounds: selected.bounds) {
                cursorForHandle(handle).set()
                return
            }
        }

        // Check if over any object body
        if doc.objectAt(point: point) != nil {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    private func cursorForHandle(_ handle: ResizeHandle) -> NSCursor {
        let symbolName: String
        switch handle {
        case .topLeft, .bottomRight:
            // ↖↘ diagonal
            symbolName = "arrow.up.left.and.arrow.down.right"
        case .topRight, .bottomLeft:
            // ↗↙ diagonal
            symbolName = "arrow.up.right.and.arrow.down.left"
        }
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) {
            return NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 8))
        }
        return NSCursor.crosshair
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(bounds)

        ctx.saveGState()
        ctx.scaleBy(x: zoomScale, y: zoomScale)

        if let img = sourceImage {
            let imgW = CGFloat(img.width)
            let imgH = CGFloat(img.height)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: imgH)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))
            ctx.restoreGState()
        }

        if let doc = document {
            for object in doc.objects {
                if let pixelate = object as? PixelateObject, let src = sourceImage {
                    pixelate.renderWithSource(in: ctx, sourceImage: src)
                } else {
                    object.render(in: ctx)
                }
            }

            if let freehand = activeFreehand {
                freehand.render(in: ctx)
            }

            if let selected = doc.selectedObject {
                drawSelectionHandles(ctx: ctx, bounds: selected.bounds)
            }

            if let start = dragStart, let current = dragCurrent,
               isDragging, activeResizeHandle == nil,
               currentTool != .select, currentTool != .freehand, currentTool != .text, currentTool != .counter, currentTool != .highlighter {
                drawPreview(ctx: ctx, from: start, to: current)
            }
        }

        ctx.restoreGState()
    }

    private func drawSelectionHandles(ctx: CGContext, bounds: CGRect) {
        let hs: CGFloat = 5
        let lw: CGFloat = 1.5
        let selColor = CGColor(red: 0, green: 0.48, blue: 1, alpha: 1)

        // Selection border
        ctx.setStrokeColor(selColor)
        ctx.setLineWidth(lw)
        ctx.stroke(bounds.insetBy(dx: -2, dy: -2))

        // Corner handles
        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
        ]
        for corner in corners {
            let r = CGRect(x: corner.x - hs, y: corner.y - hs, width: hs * 2, height: hs * 2)
            ctx.setFillColor(.white)
            ctx.fillEllipse(in: r)
            ctx.setStrokeColor(selColor)
            ctx.setLineWidth(lw)
            ctx.strokeEllipse(in: r)
        }
    }

    private func drawPreview(ctx: CGContext, from start: CGPoint, to end: CGPoint) {
        ctx.saveGState()
        ctx.setStrokeColor(currentStyle.color.cgColor)
        ctx.setLineWidth(currentStyle.lineWidth)
        ctx.setAlpha(0.6)

        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))

        switch currentTool {
        case .arrow: ctx.move(to: start); ctx.addLine(to: end); ctx.strokePath()
        case .rectangle: ctx.stroke(rect)
        case .ellipse: ctx.strokeEllipse(in: rect)
        case .pixelate: ctx.setFillColor(CGColor(gray: 0.5, alpha: 0.3)); ctx.fill(rect)
        case .crop:
            ctx.setStrokeColor(CGColor(red: 0, green: 0.48, blue: 1, alpha: 1))
            ctx.setLineDash(phase: 0, lengths: [6, 4]); ctx.stroke(rect)
        default: break
        }
        ctx.restoreGState()
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        // Make sure we own keyboard focus so subsequent keyDown events
        // (Delete, etc.) actually reach us. Safe to call even if we already are.
        window?.makeFirstResponder(self)

        guard let doc = document else { return }
        let point = toImagePoint(convert(event.locationInWindow, from: nil))
        dragStart = point
        dragCurrent = point
        isDragging = true
        activeResizeHandle = nil
        resizeOriginalTextFontSize = nil

        if currentTool == .select {
            // Check resize handles on selected object FIRST
            if let selected = doc.selectedObject {
                if let handle = handleHitTest(point: point, bounds: selected.bounds) {
                    activeResizeHandle = handle
                    resizeOriginalBounds = selected.bounds
                    if let text = selected as? TextObject {
                        resizeOriginalTextFontSize = text.fontSize
                    }
                    dragObjectID = selected.id
                    doc.beginDrag()
                    NSCursor.closedHand.set()
                    needsDisplay = true
                    return
                }
            }

            // Then check object body for move
            if let obj = doc.objectAt(point: point) {
                doc.selectObject(id: obj.id)
                dragObjectID = obj.id
                doc.beginDrag()
                NSCursor.closedHand.set()
            } else {
                doc.clearSelection()
                dragObjectID = nil
            }
        } else if currentTool == .freehand || currentTool == .highlighter {
            activeFreehand = FreehandObject(points: [point], style: currentStyle)
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = toImagePoint(convert(event.locationInWindow, from: nil))
        dragCurrent = point

        if currentTool == .select {
            if let handle = activeResizeHandle, let objID = dragObjectID,
               let origBounds = resizeOriginalBounds, let start = dragStart {
                // Resize: compute new bounds based on which handle is dragged
                resizeObject(id: objID, handle: handle, originalBounds: origBounds,
                             dragStart: start, dragCurrent: point)
            } else if let objID = dragObjectID, let start = dragStart {
                // Move
                let delta = CGSize(width: point.x - start.x, height: point.y - start.y)
                document?.moveObject(id: objID, by: delta)
                dragStart = point
            }
        } else if currentTool == .freehand || currentTool == .highlighter {
            activeFreehand?.addPoint(point)
        }

        needsDisplay = true
    }

    private func resizeObject(id: ObjectID, handle: ResizeHandle,
                              originalBounds: CGRect, dragStart: CGPoint, dragCurrent: CGPoint) {
        let dx = dragCurrent.x - dragStart.x
        let dy = dragCurrent.y - dragStart.y

        var newRect = originalBounds
        switch handle {
        case .topLeft:
            newRect.origin.x = originalBounds.minX + dx
            newRect.origin.y = originalBounds.minY + dy
            newRect.size.width = originalBounds.width - dx
            newRect.size.height = originalBounds.height - dy
        case .topRight:
            newRect.origin.y = originalBounds.minY + dy
            newRect.size.width = originalBounds.width + dx
            newRect.size.height = originalBounds.height - dy
        case .bottomLeft:
            newRect.origin.x = originalBounds.minX + dx
            newRect.size.width = originalBounds.width - dx
            newRect.size.height = originalBounds.height + dy
        case .bottomRight:
            newRect.size.width = originalBounds.width + dx
            newRect.size.height = originalBounds.height + dy
        }

        // Enforce minimum size
        if newRect.width < 10 { newRect.size.width = 10 }
        if newRect.height < 10 { newRect.size.height = 10 }

        // Apply to the object
        guard let obj = document?.objects.first(where: { $0.id == id }) else { return }
        if let rect = obj as? RectangleObject { rect.rect = newRect }
        else if let ellipse = obj as? EllipseObject { ellipse.rect = newRect }
        else if let pixelate = obj as? PixelateObject { pixelate.rect = newRect }
        else if let text = obj as? TextObject {
            // Text has intrinsic bounds derived from fontSize, so we scale fontSize
            // uniformly and then reposition origin so the corner opposite the dragged
            // handle stays fixed.
            guard let origFontSize = resizeOriginalTextFontSize,
                  originalBounds.width > 0, originalBounds.height > 0 else { return }
            let scaleX = newRect.width / originalBounds.width
            let scaleY = newRect.height / originalBounds.height
            // Use the larger scale so the text grows to fill the dragged rect.
            let scale = max(scaleX, scaleY)
            let minFontSize: CGFloat = 6
            text.fontSize = max(minFontSize, origFontSize * scale)

            // Intrinsic size after fontSize change.
            let newSize = text.bounds.size
            switch handle {
            case .topLeft:
                // Anchor: bottomRight of original bounds
                text.origin = CGPoint(
                    x: originalBounds.maxX - newSize.width,
                    y: originalBounds.maxY - newSize.height
                )
            case .topRight:
                // Anchor: bottomLeft of original bounds
                text.origin = CGPoint(
                    x: originalBounds.minX,
                    y: originalBounds.maxY - newSize.height
                )
            case .bottomLeft:
                // Anchor: topRight of original bounds
                text.origin = CGPoint(
                    x: originalBounds.maxX - newSize.width,
                    y: originalBounds.minY
                )
            case .bottomRight:
                // Anchor: topLeft of original bounds
                text.origin = originalBounds.origin
            }
        }
        else if let arrow = obj as? ArrowObject {
            switch handle {
            case .topLeft, .bottomLeft: arrow.start = CGPoint(x: newRect.minX, y: newRect.midY)
            case .topRight, .bottomRight: arrow.end = CGPoint(x: newRect.maxX, y: newRect.midY)
            }
        } else if let freehand = obj as? FreehandObject {
            // Scale all points from original bounds to new bounds
            guard originalBounds.width > 0, originalBounds.height > 0 else { return }
            let scaleX = newRect.width / originalBounds.width
            let scaleY = newRect.height / originalBounds.height
            for i in 0..<freehand.points.count {
                freehand.points[i].x = newRect.origin.x + (freehand.points[i].x - originalBounds.origin.x) * scaleX
                freehand.points[i].y = newRect.origin.y + (freehand.points[i].y - originalBounds.origin.y) * scaleY
            }
            freehand.invalidateCache()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let doc = document, let start = dragStart else {
            isDragging = false; return
        }
        let end = toImagePoint(convert(event.locationInWindow, from: nil))

        if currentTool == .select {
            dragObjectID = nil
            activeResizeHandle = nil
            resizeOriginalBounds = nil
            resizeOriginalTextFontSize = nil
        } else {
            switch currentTool {
            case .arrow:
                if hypot(end.x - start.x, end.y - start.y) > 5 / zoomScale {
                    doc.addObject(ArrowObject(start: start, end: end, style: currentStyle))
                }
            case .rectangle:
                let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                  width: abs(end.x - start.x), height: abs(end.y - start.y))
                if rect.width > 3 / zoomScale && rect.height > 3 / zoomScale {
                    doc.addObject(RectangleObject(rect: rect, style: currentStyle))
                }
            case .ellipse:
                let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                  width: abs(end.x - start.x), height: abs(end.y - start.y))
                if rect.width > 3 / zoomScale && rect.height > 3 / zoomScale {
                    doc.addObject(EllipseObject(rect: rect, style: currentStyle))
                }
            case .text:
                let alert = NSAlert()
                alert.messageText = String(localized: "Enter Text")
                alert.addButton(withTitle: String(localized: "OK"))
                alert.addButton(withTitle: String(localized: "Cancel"))
                let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
                input.stringValue = String(localized: "Text")
                alert.accessoryView = input
                if alert.runModal() == .alertFirstButtonReturn {
                    doc.addObject(TextObject(text: input.stringValue, origin: end, style: currentStyle))
                }
            case .freehand, .highlighter:
                if let freehand = activeFreehand, freehand.points.count > 2 {
                    doc.addObject(freehand)
                }
                activeFreehand = nil
            case .pixelate:
                let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                  width: abs(end.x - start.x), height: abs(end.y - start.y))
                if rect.width > 5 / zoomScale && rect.height > 5 / zoomScale {
                    doc.addObject(PixelateObject(rect: rect, blockSize: currentStyle.lineWidth))
                }
            case .counter:
                let number = nextCounterNumber()
                let counter = CounterObject(center: end, number: number, radius: currentStyle.lineWidth, style: currentStyle)
                doc.addObject(counter)
            case .crop, .select:
                break
            }
        }

        isDragging = false
        dragStart = nil
        dragCurrent = nil
        needsDisplay = true
        onDocumentChanged?()

        if currentTool != .select {
            onObjectCreated?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            document?.removeSelected()
            needsDisplay = true
            onDocumentChanged?()
        } else {
            super.keyDown(with: event)
        }
    }
}
