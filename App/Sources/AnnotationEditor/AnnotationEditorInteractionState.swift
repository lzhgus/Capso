import AppKit

final class AnnotationEditorInteractionState {
    private let copySuppressionGrace: TimeInterval = 1.0
    private var suppressCopyUntil = Date.distantPast

    var isEditingText = false
    var isInteractingWithCanvas = false

    var shouldSuppressCopyAction: Bool {
        isEditingText || isInteractingWithCanvas || Date() < suppressCopyUntil
    }

    func setCanvasInteraction(_ isInteracting: Bool) {
        isInteractingWithCanvas = isInteracting
        suppressCopyUntil = isInteracting
            ? .distantFuture
            : Date().addingTimeInterval(copySuppressionGrace)
    }

    func shouldSuppressCopyShortcut(for event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command,
              event.charactersIgnoringModifiers?.lowercased() == "c" else {
            return false
        }
        return shouldSuppressCopyAction
    }
}
