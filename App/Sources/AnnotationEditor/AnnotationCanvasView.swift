// App/Sources/AnnotationEditor/AnnotationCanvasView.swift
import SwiftUI
import AppKit
import AnnotationKit

struct AnnotationCanvasView: NSViewRepresentable {
    let document: AnnotationDocument
    let sourceImage: CGImage
    let currentTool: AnnotationTool
    let currentStyle: AnnotationKit.StrokeStyle
    let redactionMode: RedactionMode
    /// Font size for the text tool / active inline edit. Bound to the
    /// font-size slider in SwiftUI.
    let textFontSize: CGFloat
    let textFillColor: AnnotationColor?
    let textOutlineColor: AnnotationColor?
    let textGlyphStrokeColor: AnnotationColor?
    let zoomScale: CGFloat
    let refreshTrigger: Int
    var textRegions: [CGRect] = []
    var commitEditingTrigger: Int = 0
    var onDocumentChanged: (() -> Void)?
    var onSwitchToSelect: (() -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?
    /// Called when the inline text editor appears. Passes the effective
    /// fontSize (existing object's size when re-editing, current slider
    /// value for a new edit). SwiftUI flips `isEditingText` and — for
    /// re-edits — syncs the size slider.
    var onTextEditingStarted: ((CGFloat, Bool, Bool, Bool) -> Void)?
    /// Called when the inline text editor commits / dismisses.
    var onTextEditingEnded: (() -> Void)?
    /// Called for each trackpad pinch step. Passes the per-event magnification
    /// delta and the focal location in canvas (flipped, top-left) coordinates.
    /// Optional — canvases that don't support gesture zoom simply leave it nil.
    var onMagnify: ((CGFloat, CGPoint) -> Void)?

    /// Tools that stay active after each stroke so the user can keep drawing
    /// without reaching back to the toolbar (issue #75). Shape tools (arrow,
    /// rectangle, ellipse) and pixelate behave the same way — most users add
    /// several in a row. Text and crop intentionally stay one-shot: text has
    /// its own inline-edit flow and crop is naturally one-per-image.
    private static let stickyTools: Set<AnnotationTool> = [
        .arrow, .line, .rectangle, .ellipse, .pixelate,
        .counter, .freehand, .highlighter
    ]

    func makeNSView(context: Context) -> AnnotationCanvasNSView {
        let view = AnnotationCanvasNSView()
        view.document = document
        view.sourceImage = sourceImage
        view.currentTool = currentTool
        view.currentStyle = currentStyle
        view.redactionMode = redactionMode
        view.currentTextFontSize = textFontSize
        view.currentTextFillColor = textFillColor
        view.currentTextOutlineColor = textOutlineColor
        view.currentTextGlyphStrokeColor = textGlyphStrokeColor
        view.zoomScale = zoomScale
        view.textRegions = textRegions
        view.onDocumentChanged = { onDocumentChanged?() }
        view.onInteractionChanged = { isInteracting in
            onInteractionChanged?(isInteracting)
        }
        view.onObjectCreated = {
            if !Self.stickyTools.contains(currentTool) {
                onSwitchToSelect?()
            }
        }
        view.onTextEditingStarted = { fontSize, hasFill, hasOutline, hasStroke in
            onTextEditingStarted?(fontSize, hasFill, hasOutline, hasStroke)
        }
        view.onTextEditingEnded = { onTextEditingEnded?() }
        // Pass the optional through directly: a nil here must stay nil so the
        // NSView forwards pinch to an enclosing scroll view (main editor) instead
        // of swallowing it in a no-op wrapper.
        view.onMagnify = onMagnify
        return view
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func updateNSView(_ nsView: AnnotationCanvasNSView, context: Context) {
        let toolChanged = nsView.currentTool != currentTool
        nsView.sourceImage = sourceImage
        nsView.currentTool = currentTool
        nsView.currentStyle = currentStyle
        nsView.redactionMode = redactionMode
        nsView.currentTextFontSize = textFontSize
        nsView.currentTextFillColor = textFillColor
        nsView.currentTextOutlineColor = textOutlineColor
        nsView.currentTextGlyphStrokeColor = textGlyphStrokeColor
        nsView.zoomScale = zoomScale
        nsView.textRegions = textRegions
        nsView.onDocumentChanged = { onDocumentChanged?() }
        nsView.onInteractionChanged = { isInteracting in
            onInteractionChanged?(isInteracting)
        }
        nsView.onObjectCreated = {
            if !Self.stickyTools.contains(currentTool) {
                onSwitchToSelect?()
            }
        }
        nsView.onTextEditingStarted = { fontSize, hasFill, hasOutline, hasStroke in
            onTextEditingStarted?(fontSize, hasFill, hasOutline, hasStroke)
        }
        nsView.onTextEditingEnded = { onTextEditingEnded?() }
        nsView.onMagnify = onMagnify
        if context.coordinator.lastCommitEditingTrigger != commitEditingTrigger {
            context.coordinator.lastCommitEditingTrigger = commitEditingTrigger
            nsView.commitTextEditingIfNeeded()
        }
        nsView.needsDisplay = true
        if toolChanged {
            nsView.window?.invalidateCursorRects(for: nsView)
        }
    }

    final class Coordinator {
        var lastCommitEditingTrigger = 0
    }
}
