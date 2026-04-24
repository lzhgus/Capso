// App/Sources/AnnotationEditor/AnnotationCanvasView.swift
import SwiftUI
import AppKit
import AnnotationKit

struct AnnotationCanvasView: NSViewRepresentable {
    let document: AnnotationDocument
    let sourceImage: CGImage
    let currentTool: AnnotationTool
    let currentStyle: AnnotationKit.StrokeStyle
    /// Font size for the text tool / active inline edit. Bound to the
    /// font-size slider in SwiftUI.
    let textFontSize: CGFloat
    let zoomScale: CGFloat
    let refreshTrigger: Int
    var textRegions: [CGRect] = []
    var onSwitchToSelect: (() -> Void)?
    /// Called when the inline text editor appears. Passes the effective
    /// fontSize (existing object's size when re-editing, current slider
    /// value for a new edit). SwiftUI flips `isEditingText` and — for
    /// re-edits — syncs the size slider.
    var onTextEditingStarted: ((CGFloat) -> Void)?
    /// Called when the inline text editor commits / dismisses.
    var onTextEditingEnded: (() -> Void)?

    func makeNSView(context: Context) -> AnnotationCanvasNSView {
        let view = AnnotationCanvasNSView()
        view.document = document
        view.sourceImage = sourceImage
        view.currentTool = currentTool
        view.currentStyle = currentStyle
        view.currentTextFontSize = textFontSize
        view.zoomScale = zoomScale
        view.textRegions = textRegions
        view.onObjectCreated = {
            // Continuous-drawing tools stay active after each stroke;
            // one-shot tools (arrow, rect, ellipse, text, pixelate) switch
            // back to select after creation.
            let keepActive: Set<AnnotationTool> = [.counter, .freehand, .highlighter]
            if !keepActive.contains(currentTool) {
                onSwitchToSelect?()
            }
        }
        view.onTextEditingStarted = { fontSize in onTextEditingStarted?(fontSize) }
        view.onTextEditingEnded = { onTextEditingEnded?() }
        return view
    }

    func updateNSView(_ nsView: AnnotationCanvasNSView, context: Context) {
        let toolChanged = nsView.currentTool != currentTool
        nsView.currentTool = currentTool
        nsView.currentStyle = currentStyle
        nsView.currentTextFontSize = textFontSize
        nsView.zoomScale = zoomScale
        nsView.textRegions = textRegions
        nsView.onObjectCreated = {
            let keepActive: Set<AnnotationTool> = [.counter, .freehand, .highlighter]
            if !keepActive.contains(currentTool) {
                onSwitchToSelect?()
            }
        }
        nsView.onTextEditingStarted = { fontSize in onTextEditingStarted?(fontSize) }
        nsView.onTextEditingEnded = { onTextEditingEnded?() }
        nsView.needsDisplay = true
        if toolChanged {
            nsView.window?.invalidateCursorRects(for: nsView)
        }
    }
}
