// Packages/AnnotationKit/Sources/AnnotationKit/AnnotationEscapePolicy.swift

public enum AnnotationEscapeAction: Equatable, Sendable {
    case commitTextEditing
    case exitCropMode
    case switchToSelectTool
    case clearSelection
    case none
}

/// Decides what pressing Esc should do in the annotation editor. Esc never
/// closes the editor — it only ever backs the user out one step at a time:
/// finish text editing, then leave crop mode, then drop back to the select
/// tool, then clear a selection, then do nothing.
public enum AnnotationEscapePolicy {
    public static func action(
        isEditingText: Bool,
        isCropMode: Bool,
        currentTool: AnnotationTool,
        hasSelection: Bool
    ) -> AnnotationEscapeAction {
        if isEditingText { return .commitTextEditing }
        if isCropMode { return .exitCropMode }
        if currentTool != .select { return .switchToSelectTool }
        if hasSelection { return .clearSelection }
        return .none
    }
}
