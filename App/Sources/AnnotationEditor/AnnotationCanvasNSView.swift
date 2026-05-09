// App/Sources/AnnotationEditor/AnnotationCanvasNSView.swift
import AppKit
import CoreGraphics
import AnnotationKit

/// Which visible handle is being dragged for resize or path adjustment.
private enum ResizeHandle {
    case topLeft, topRight, bottomLeft, bottomRight
    case pathStart, pathEnd, pathControl
}

private protocol PathEditableAnnotation: AnnotationObject {
    var start: CGPoint { get set }
    var end: CGPoint { get set }
    var controlPoint: CGPoint? { get set }
}

extension LineObject: PathEditableAnnotation {}
extension ArrowObject: PathEditableAnnotation {}

@MainActor
final class AnnotationCanvasNSView: NSView {
    var document: AnnotationDocument?
    var sourceImage: CGImage?
    var currentTool: AnnotationTool = .select
    var currentStyle: StrokeStyle = StrokeStyle() {
        didSet { syncEditorStyle() }
    }
    var redactionMode: RedactionMode = .pixelate
    /// Font size used for newly created TextObjects and propagated live to
    /// the inline editor. Pushed from SwiftUI by AnnotationCanvasView.
    var currentTextFontSize: CGFloat = 48 {
        didSet { textEditor?.fontSize = currentTextFontSize }
    }
    var onDocumentChanged: (() -> Void)?
    var onObjectCreated: (() -> Void)?
    /// Fired when an inline text edit begins. Passes the effective fontSize
    /// (matches the existing object when re-editing, or `currentTextFontSize`
    /// for a fresh edit). SwiftUI uses it to flip `isEditingText` and — for
    /// double-click re-edits — to sync the font-size slider to the object.
    var onTextEditingStarted: ((CGFloat) -> Void)?
    /// Fired on commit / cancel.
    var onTextEditingEnded: (() -> Void)?

    func commitTextEditingIfNeeded() {
        commitTextEditing()
    }

    var zoomScale: CGFloat = 1.0 {
        didSet {
            guard zoomScale != oldValue, let editor = textEditor else { return }
            editor.zoomScale = zoomScale
            repositionEditor()
        }
    }

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var isDragging = false
    private var dragObjectID: ObjectID?
    private var activeResizeHandle: ResizeHandle?
    private var resizeOriginalBounds: CGRect?
    private var resizeOriginalFreehandPoints: [CGPoint]?
    private var resizeOriginalEndpoints: (start: CGPoint, end: CGPoint)?
    private var resizeOriginalLineControlPoint: CGPoint?
    /// Original fontSize captured when a TextObject resize drag begins.
    /// Text uses intrinsic sizing (bounds derived from fontSize), so we scale
    /// fontSize from this original value — not the live one, which drifts each tick.
    private var resizeOriginalTextFontSize: CGFloat?
    private var activeFreehand: FreehandObject?
    /// Cached text regions from OCR for smart highlighter snapping.
    var textRegions: [CGRect] = []
    /// When the highlighter starts on a text line, stores the line's
    /// bounding box so the stroke is constrained to a horizontal band.
    private var highlighterSnapRect: CGRect?

    // MARK: - Inline text editing state

    /// The currently-visible inline editor, if any.
    private var textEditor: AnnotationTextEditor?
    /// When re-editing an existing TextObject (double-click), holds it so we
    /// can mutate it on commit rather than creating a new object.
    private var editingOriginalObject: TextObject?

    private let handleRadius: CGFloat = 5  // in image coords (adjusted by zoom in drawing)

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

    private func handleHitTest(point: CGPoint, object: any AnnotationObject) -> ResizeHandle? {
        if let pathObject = object as? any PathEditableAnnotation {
            return pathHandleHitTest(point: point, object: pathObject)
        }

        let r = max(10 / max(zoomScale, 0.1), handleRadius + 4)
        for (handle, corner) in selectionHandleCenters(for: object.bounds) {
            if hypot(point.x - corner.x, point.y - corner.y) <= r {
                return handle
            }
        }
        return nil
    }

    private func pathHandleHitTest(point: CGPoint, object: any PathEditableAnnotation) -> ResizeHandle? {
        let r = max(10 / max(zoomScale, 0.1), handleRadius + 4)
        for (handle, center) in pathHandleCenters(for: object) {
            if hypot(point.x - center.x, point.y - center.y) <= r {
                return handle
            }
        }
        return nil
    }

    // MARK: - Cursor Management

    override func resetCursorRects() {
        discardCursorRects()
        let cursor: NSCursor = currentTool == .select ? .arrow : .crosshair
        addCursorRect(visibleRect, cursor: cursor)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = toImagePoint(convert(event.locationInWindow, from: nil))
        guard let doc = document else { return }

        if let selected = doc.selectedObject {
            if let handle = handleHitTest(point: point, object: selected) {
                cursorForHandle(handle).set()
                return
            }
        }

        if currentTool == .select, doc.objectAt(point: point) != nil {
            NSCursor.openHand.set()
        } else if currentTool == .select {
            NSCursor.arrow.set()
        } else {
            NSCursor.crosshair.set()
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
        case .pathStart, .pathEnd, .pathControl:
            return NSCursor.openHand
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
                // While a TextObject is being re-edited inline, hide it from
                // the canvas render so we don't double-draw the text under
                // the live editor.
                if let text = object as? TextObject, text === editingOriginalObject {
                    continue
                }
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
                if let pathObject = selected as? any PathEditableAnnotation {
                    drawPathSelectionHandles(ctx: ctx, object: pathObject)
                } else {
                    drawSelectionHandles(ctx: ctx, bounds: selected.bounds)
                }
            }

            if let start = dragStart, let current = dragCurrent,
               isDragging, activeResizeHandle == nil,
               currentTool != .select, currentTool != .freehand, currentTool != .text, currentTool != .counter, currentTool != .highlighter {
                drawPreview(ctx: ctx, from: start, to: current)
            }
        }

        ctx.restoreGState()
    }

    private func drawPathSelectionHandles(ctx: CGContext, object: any PathEditableAnnotation) {
        ctx.saveGState()

        let scale = max(zoomScale, 0.1)
        let endpointSize: CGFloat = 8 / scale
        let controlSize: CGFloat = 7 / scale
        let lw: CGFloat = 1.5 / scale
        let accent = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        let controlFill = NSColor.white.withAlphaComponent(0.92).cgColor

        if let controlPoint = object.controlPoint {
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.36).cgColor)
            ctx.setLineWidth(1 / scale)
            ctx.setLineDash(phase: 0, lengths: [3 / scale, 4 / scale])
            ctx.move(to: object.start)
            ctx.addLine(to: controlPoint)
            ctx.addLine(to: object.end)
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        for (_, center) in [(ResizeHandle.pathStart, object.start), (.pathEnd, object.end)] {
            let rect = CGRect(
                x: center.x - endpointSize / 2,
                y: center.y - endpointSize / 2,
                width: endpointSize,
                height: endpointSize
            )
            ctx.setFillColor(accent)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.92).cgColor)
            ctx.setLineWidth(lw)
            ctx.strokeEllipse(in: rect.insetBy(dx: lw / 2, dy: lw / 2))
        }

        let controlPoint = object.controlPoint ?? pathMidpoint(object)
        let controlRect = CGRect(
            x: controlPoint.x - controlSize / 2,
            y: controlPoint.y - controlSize / 2,
            width: controlSize,
            height: controlSize
        )
        ctx.setFillColor(controlFill)
        ctx.fillEllipse(in: controlRect)
        ctx.setStrokeColor(accent)
        ctx.setLineWidth(lw)
        ctx.strokeEllipse(in: controlRect.insetBy(dx: lw / 2, dy: lw / 2))

        ctx.restoreGState()
    }

    private func pathHandleCenters(for object: any PathEditableAnnotation) -> [(ResizeHandle, CGPoint)] {
        [
            (.pathStart, object.start),
            (.pathEnd, object.end),
            (.pathControl, object.controlPoint ?? pathMidpoint(object)),
        ]
    }

    private func pathMidpoint(_ object: any PathEditableAnnotation) -> CGPoint {
        CGPoint(x: (object.start.x + object.end.x) / 2, y: (object.start.y + object.end.y) / 2)
    }

    private func drawSelectionHandles(ctx: CGContext, bounds: CGRect) {
        ctx.saveGState()

        let scale = max(zoomScale, 0.1)
        let hs: CGFloat = 4 / scale
        let lw: CGFloat = 1 / scale
        let selColor = NSColor.controlAccentColor.withAlphaComponent(0.78).cgColor
        let frame = selectionFrame(for: bounds)

        // Selection border
        ctx.setStrokeColor(selColor)
        ctx.setLineWidth(lw)
        ctx.setLineDash(phase: 0, lengths: [4 / scale, 3 / scale])
        ctx.stroke(frame)
        ctx.setLineDash(phase: 0, lengths: [])

        // Corner handles
        for (_, corner) in selectionHandleCenters(for: bounds) {
            let r = CGRect(x: corner.x - hs, y: corner.y - hs, width: hs * 2, height: hs * 2)
            ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor)
            ctx.fillEllipse(in: r)
            ctx.setStrokeColor(selColor)
            ctx.setLineWidth(lw)
            ctx.strokeEllipse(in: r)
        }

        ctx.restoreGState()
    }

    private func selectionFrame(for bounds: CGRect) -> CGRect {
        let outset = 6 / max(zoomScale, 0.1)
        return bounds.insetBy(dx: -outset, dy: -outset)
    }

    private func selectionHandleCenters(for bounds: CGRect) -> [(ResizeHandle, CGPoint)] {
        let frame = selectionFrame(for: bounds)
        return [
            (.topLeft, CGPoint(x: frame.minX, y: frame.minY)),
            (.topRight, CGPoint(x: frame.maxX, y: frame.minY)),
            (.bottomLeft, CGPoint(x: frame.minX, y: frame.maxY)),
            (.bottomRight, CGPoint(x: frame.maxX, y: frame.maxY)),
        ]
    }

    private func drawPreview(ctx: CGContext, from start: CGPoint, to end: CGPoint) {
        ctx.saveGState()
        ctx.setStrokeColor(currentStyle.color.cgColor)
        ctx.setLineWidth(currentStyle.lineWidth)
        ctx.setAlpha(0.6)

        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))

        switch currentTool {
        case .arrow, .line: ctx.move(to: start); ctx.addLine(to: end); ctx.strokePath()
        case .rectangle: ctx.stroke(rect)
        case .ellipse: ctx.strokeEllipse(in: rect)
        case .pixelate: ctx.setFillColor(CGColor(gray: 0.5, alpha: 0.3)); ctx.fill(rect)
        default: break
        }
        ctx.restoreGState()
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        // If we're currently editing a text object, any click *outside* the
        // editor commits the edit; clicks inside are forwarded to the editor.
        if let editor = textEditor {
            let pointInSelf = convert(event.locationInWindow, from: nil)
            if editor.containsCanvasPoint(pointInSelf) {
                // Let the NSTextView handle the click (focus / caret placement).
                super.mouseDown(with: event)
                return
            } else {
                commitTextEditing()
                // Fall through: the click should still be processed as a fresh
                // canvas interaction (e.g. create another text box, select, etc.).
            }
        }

        // Make sure we own keyboard focus so subsequent keyDown events
        // (Delete, etc.) actually reach us. Safe to call even if we already are.
        window?.makeKey()
        window?.makeFirstResponder(self)

        guard let doc = document else { return }
        let point = toImagePoint(convert(event.locationInWindow, from: nil))
        dragStart = point
        dragCurrent = point
        isDragging = true
        activeResizeHandle = nil
        resizeOriginalTextFontSize = nil
        resizeOriginalFreehandPoints = nil
        resizeOriginalEndpoints = nil
        resizeOriginalLineControlPoint = nil

        if let selected = doc.selectedObject,
           let handle = handleHitTest(point: point, object: selected) {
            activeResizeHandle = handle
            resizeOriginalBounds = selected.bounds
            resizeOriginalFreehandPoints = (selected as? FreehandObject)?.points
            if let arrow = selected as? ArrowObject {
                resizeOriginalEndpoints = (arrow.start, arrow.end)
                resizeOriginalLineControlPoint = arrow.controlPoint ?? pathMidpoint(arrow)
            } else if let line = selected as? LineObject {
                resizeOriginalEndpoints = (line.start, line.end)
                resizeOriginalLineControlPoint = line.controlPoint ?? pathMidpoint(line)
            }
            if let text = selected as? TextObject {
                resizeOriginalTextFontSize = text.fontSize
            }
            dragObjectID = selected.id
            doc.beginDrag()
            cursorForHandle(handle).set()
            needsDisplay = true
            return
        }

        if currentTool == .select {
            // Double-click a TextObject → enter inline edit mode.
            if event.clickCount == 2, let obj = doc.objectAt(point: point),
               let text = obj as? TextObject {
                isDragging = false
                beginTextEditing(at: text.origin, existing: text)
                return
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
            // Smart highlighter: if starting on a text line, snap to it.
            highlighterSnapRect = nil
            if currentTool == .highlighter {
                // Use a slightly expanded region for easier hit detection
                for region in textRegions {
                    let expanded = region.insetBy(dx: 0, dy: -region.height * 0.3)
                    if expanded.contains(point) {
                        highlighterSnapRect = region
                        break
                    }
                }
            }
            if let snap = highlighterSnapRect {
                let snappedY = snap.midY
                let snappedPoint = CGPoint(x: point.x, y: snappedY)
                activeFreehand = FreehandObject(points: [snappedPoint], style: currentStyle)
            } else {
                activeFreehand = FreehandObject(points: [point], style: currentStyle)
            }
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = toImagePoint(convert(event.locationInWindow, from: nil))
        dragCurrent = point

        if let handle = activeResizeHandle, let objID = dragObjectID,
           let origBounds = resizeOriginalBounds, let start = dragStart {
            // Resize handles remain active even while a drawing tool is selected.
            resizeObject(id: objID, handle: handle, originalBounds: origBounds,
                         dragStart: start, dragCurrent: point)
        } else if currentTool == .select {
            if let objID = dragObjectID, let start = dragStart {
                // Move
                let delta = CGSize(width: point.x - start.x, height: point.y - start.y)
                document?.moveObject(id: objID, by: delta)
                dragStart = point
            }
        } else if currentTool == .freehand || currentTool == .highlighter {
            if let snap = highlighterSnapRect {
                // Constrain to horizontal line at the text's vertical center
                let snappedPoint = CGPoint(x: point.x, y: snap.midY)
                activeFreehand?.addPoint(snappedPoint)
            } else {
                activeFreehand?.addPoint(point)
            }
        }

        needsDisplay = true
    }

    private func resizeObject(id: ObjectID, handle: ResizeHandle,
                              originalBounds: CGRect, dragStart: CGPoint, dragCurrent: CGPoint) {
        let dx = dragCurrent.x - dragStart.x
        let dy = dragCurrent.y - dragStart.y

        guard let obj = document?.objects.first(where: { $0.id == id }) else { return }
        if let pathObject = obj as? any PathEditableAnnotation {
            guard let endpoints = resizeOriginalEndpoints else { return }
            switch handle {
            case .pathStart:
                pathObject.start = CGPoint(x: endpoints.start.x + dx, y: endpoints.start.y + dy)
            case .pathEnd:
                pathObject.end = CGPoint(x: endpoints.end.x + dx, y: endpoints.end.y + dy)
            case .pathControl:
                let original = resizeOriginalLineControlPoint ?? CGPoint(
                    x: (endpoints.start.x + endpoints.end.x) / 2,
                    y: (endpoints.start.y + endpoints.end.y) / 2
                )
                pathObject.controlPoint = CGPoint(x: original.x + dx, y: original.y + dy)
            default:
                break
            }
            return
        }

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
        case .pathStart, .pathEnd, .pathControl:
            return
        }

        // Enforce minimum size
        if newRect.width < 10 { newRect.size.width = 10 }
        if newRect.height < 10 { newRect.size.height = 10 }

        // Apply to the object
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
            case .pathStart, .pathEnd, .pathControl:
                break
            }
        }
        else if let arrow = obj as? ArrowObject {
            guard let endpoints = resizeOriginalEndpoints else { return }
            arrow.start = scaledPoint(endpoints.start, from: originalBounds, to: newRect)
            arrow.end = scaledPoint(endpoints.end, from: originalBounds, to: newRect)
        } else if let line = obj as? LineObject {
            guard let endpoints = resizeOriginalEndpoints else { return }
            line.start = scaledPoint(endpoints.start, from: originalBounds, to: newRect)
            line.end = scaledPoint(endpoints.end, from: originalBounds, to: newRect)
        } else if let freehand = obj as? FreehandObject {
            // Scale all points from original bounds to new bounds
            guard originalBounds.width > 0, originalBounds.height > 0,
                  let originalPoints = resizeOriginalFreehandPoints else { return }
            let scaleX = newRect.width / originalBounds.width
            let scaleY = newRect.height / originalBounds.height
            for i in 0..<min(freehand.points.count, originalPoints.count) {
                freehand.points[i].x = newRect.origin.x + (originalPoints[i].x - originalBounds.origin.x) * scaleX
                freehand.points[i].y = newRect.origin.y + (originalPoints[i].y - originalBounds.origin.y) * scaleY
            }
            freehand.invalidateCache()
        }
    }

    private func scaledPoint(_ point: CGPoint, from originalBounds: CGRect, to newRect: CGRect) -> CGPoint {
        guard originalBounds.width > 0, originalBounds.height > 0 else { return point }
        return CGPoint(
            x: newRect.origin.x + (point.x - originalBounds.origin.x) * (newRect.width / originalBounds.width),
            y: newRect.origin.y + (point.y - originalBounds.origin.y) * (newRect.height / originalBounds.height)
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard let doc = document, let start = dragStart else {
            isDragging = false; return
        }
        let end = toImagePoint(convert(event.locationInWindow, from: nil))

        if activeResizeHandle != nil {
            dragObjectID = nil
            activeResizeHandle = nil
            resizeOriginalBounds = nil
            resizeOriginalTextFontSize = nil
            resizeOriginalFreehandPoints = nil
            resizeOriginalEndpoints = nil
            resizeOriginalLineControlPoint = nil
            isDragging = false
            dragStart = nil
            dragCurrent = nil
            needsDisplay = true
            onDocumentChanged?()
            return
        }

        if currentTool == .select {
            dragObjectID = nil
            activeResizeHandle = nil
            resizeOriginalBounds = nil
            resizeOriginalTextFontSize = nil
            resizeOriginalFreehandPoints = nil
            resizeOriginalEndpoints = nil
            resizeOriginalLineControlPoint = nil
        } else {
            switch currentTool {
            case .arrow:
                if hypot(end.x - start.x, end.y - start.y) > 5 / zoomScale {
                    doc.addObject(ArrowObject(start: start, end: end, style: currentStyle))
                }
            case .line:
                if hypot(end.x - start.x, end.y - start.y) > 5 / zoomScale {
                    doc.addObject(LineObject(start: start, end: end, style: currentStyle))
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
                // Inline editor replaces the old NSAlert popup. Spawn at the
                // click point; commit happens on Esc or outside-click.
                beginTextEditing(at: end, existing: nil)
                // Skip the normal post-create path — creation is deferred to
                // commitTextEditing, and we do NOT want to switch back to
                // select tool yet (user hasn't typed anything).
                isDragging = false
                dragStart = nil
                dragCurrent = nil
                needsDisplay = true
                return
            case .freehand, .highlighter:
                if let freehand = activeFreehand, freehand.points.count > 1 {
                    doc.addObject(freehand)
                }
                activeFreehand = nil
                highlighterSnapRect = nil
            case .pixelate:
                let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                  width: abs(end.x - start.x), height: abs(end.y - start.y))
                if rect.width > 5 / zoomScale && rect.height > 5 / zoomScale {
                    let redaction = PixelateObject(
                        rect: rect,
                        blockSize: currentStyle.lineWidth,
                        mode: redactionMode
                    )
                    redaction.style = currentStyle
                    doc.addObject(redaction)
                }
            case .counter:
                let number = nextCounterNumber()
                let counter = CounterObject(center: end, number: number, radius: currentStyle.lineWidth, style: currentStyle)
                doc.addObject(counter)
            case .select:
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

    // MARK: - Inline text editing

    /// Begin an inline text edit at `imagePoint` (image coordinates).
    /// Pass an `existing` TextObject for double-click re-edit; pass `nil` for
    /// a fresh text creation.
    private func beginTextEditing(at imagePoint: CGPoint, existing: TextObject?) {
        // If one is already up, finish it before opening a new one.
        if textEditor != nil { commitTextEditing() }

        let editor = AnnotationTextEditor(frame: .zero)
        editor.delegate = self
        editor.zoomScale = zoomScale
        editor.imageOrigin = imagePoint

        if let existing {
            editor.fontSize = existing.fontSize
            editor.fontName = existing.fontName
            editor.textColor = existing.style.color.nsColor
                .withAlphaComponent(existing.style.opacity)
            editor.beginEditing(initialText: existing.text)
            editingOriginalObject = existing
        } else {
            editor.fontSize = currentTextFontSize
            editor.textColor = currentStyle.color.nsColor
                .withAlphaComponent(currentStyle.opacity)
            editor.beginEditing(initialText: "")
            editingOriginalObject = nil
        }

        addSubview(editor)
        textEditor = editor
        repositionEditor()
        editor.focusTextView()
        needsDisplay = true

        // Notify SwiftUI so the toolbar can flip into font-size mode and
        // — for re-edits — sync the slider to the object's fontSize.
        onTextEditingStarted?(editor.fontSize)
    }

    /// Position the editor's frame based on its `imageOrigin` and the current
    /// zoom. Called on create, on zoom change, and on content resize.
    private func repositionEditor() {
        guard let editor = textEditor else { return }
        let viewOrigin = CGPoint(
            x: editor.imageOrigin.x * zoomScale,
            y: editor.imageOrigin.y * zoomScale
        )
        editor.setFrameOrigin(viewOrigin)
    }

    /// Finalize the edit: create / mutate / delete a TextObject depending on
    /// the combination of (editingOriginalObject, text) and tear down the
    /// inline editor.
    private func commitTextEditing() {
        guard let editor = textEditor, let doc = document else { return }

        let finalText = editor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let origin = editor.imageOrigin

        if let existing = editingOriginalObject {
            if finalText.isEmpty {
                // Edited to empty → delete the original.
                doc.removeObject(id: existing.id)
            } else if finalText != existing.text || editor.fontSize != existing.fontSize {
                // Mutated text or fontSize — push one undo step, then update.
                doc.beginDrag()
                existing.text = finalText
                existing.fontSize = editor.fontSize
            }
        } else if !finalText.isEmpty {
            // Fresh edit with content → create a new TextObject using the
            // editor's current style (which reflects live toolbar changes).
            let newObj = TextObject(
                text: finalText,
                origin: origin,
                fontSize: editor.fontSize,
                style: currentStyle
            )
            doc.addObject(newObj)
        }
        // else: fresh edit with empty text → just discard.

        // Tear down the editor.
        editor.removeFromSuperview()
        textEditor = nil
        editingOriginalObject = nil

        needsDisplay = true
        window?.makeFirstResponder(self)
        onDocumentChanged?()
        onTextEditingEnded?()

        // Creation path: switch back to select, matching the other one-shot
        // tools (arrow / rect / ellipse / pixelate).
        if currentTool == .text {
            onObjectCreated?()
        }
    }

    /// When `currentStyle` changes (toolbar color / opacity) and we're mid-edit,
    /// push the new color into the editor so the typed text re-renders live.
    private func syncEditorStyle() {
        guard let editor = textEditor else { return }
        editor.textColor = currentStyle.color.nsColor
            .withAlphaComponent(currentStyle.opacity)
    }
}

// MARK: - AnnotationTextEditorDelegate

extension AnnotationCanvasNSView: AnnotationTextEditorDelegate {
    func textEditor(_ editor: AnnotationTextEditor, didCommitText text: String) {
        // Editor is asking us to finalize (Esc pressed). Outside-click commits
        // are handled directly in mouseDown.
        commitTextEditing()
    }
}
