// Packages/AnnotationKit/Tests/AnnotationKitTests/AnnotationEscapePolicyTests.swift
import Testing
@testable import AnnotationKit

@Suite("AnnotationEscapePolicy")
struct AnnotationEscapePolicyTests {
    @Test("Text editing takes precedence over everything else")
    func textEditingWinsOverEverything() {
        let action = AnnotationEscapePolicy.action(
            isEditingText: true,
            isCropMode: true,
            currentTool: .arrow,
            hasSelection: true
        )
        #expect(action == .commitTextEditing)
    }

    @Test("Crop mode beats switching tools", arguments: [
        (AnnotationTool.arrow, false),
        (AnnotationTool.select, true)
    ])
    func cropModeBeatsToolSwitch(tool: AnnotationTool, hasSelection: Bool) {
        let action = AnnotationEscapePolicy.action(
            isEditingText: false,
            isCropMode: true,
            currentTool: tool,
            hasSelection: hasSelection
        )
        #expect(action == .exitCropMode)
    }

    @Test("Any non-select tool switches back to select", arguments: [
        AnnotationTool.arrow, .line, .rectangle, .ellipse, .text, .freehand, .pixelate, .counter, .highlighter
    ], [true, false])
    func nonSelectToolSwitchesToSelect(tool: AnnotationTool, hasSelection: Bool) {
        let action = AnnotationEscapePolicy.action(
            isEditingText: false,
            isCropMode: false,
            currentTool: tool,
            hasSelection: hasSelection
        )
        #expect(action == .switchToSelectTool)
    }

    @Test("Select tool with a selection clears it")
    func selectToolWithSelectionClearsIt() {
        let action = AnnotationEscapePolicy.action(
            isEditingText: false,
            isCropMode: false,
            currentTool: .select,
            hasSelection: true
        )
        #expect(action == .clearSelection)
    }

    @Test("Select tool with nothing selected does nothing — Esc never closes the editor")
    func selectToolWithNothingDoesNothing() {
        let action = AnnotationEscapePolicy.action(
            isEditingText: false,
            isCropMode: false,
            currentTool: .select,
            hasSelection: false
        )
        #expect(action == .none)
    }
}
