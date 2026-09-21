import SwiftUI
import AnnotationKit

struct CropAreaView: NSViewRepresentable {
    @Binding var cropRect: CGRect
    let imageSize: CGSize
    let zoomScale: CGFloat
    let aspectRatio: CGFloat?
    let snapEnabled: Bool
    /// Called with the rect that was in effect BEFORE the gesture. The owner
    /// uses it to push a single undo entry per drag.
    var onDragEnded: ((CGRect) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    func makeNSView(context: Context) -> CropAreaNSView {
        let view = CropAreaNSView()
        view.imageSize = imageSize
        view.zoomScale = zoomScale
        view.cropRect = cropRect
        view.aspectRatio = aspectRatio
        view.snapEnabled = snapEnabled
        view.onCropRectChanged = { newRect in
            DispatchQueue.main.async {
                if cropRect != newRect { cropRect = newRect }
            }
        }
        view.onDragEnded = { oldRect in
            DispatchQueue.main.async { onDragEnded?(oldRect) }
        }
        view.onCommitRequested = onCommit
        view.onCancelRequested = onCancel
        return view
    }

    func updateNSView(_ nsView: CropAreaNSView, context: Context) {
        nsView.imageSize = imageSize
        nsView.zoomScale = zoomScale
        nsView.aspectRatio = aspectRatio
        nsView.snapEnabled = snapEnabled
        nsView.onCommitRequested = onCommit
        nsView.onCancelRequested = onCancel
        if nsView.cropRect != cropRect {
            nsView.cropRect = cropRect
        }
    }
}
