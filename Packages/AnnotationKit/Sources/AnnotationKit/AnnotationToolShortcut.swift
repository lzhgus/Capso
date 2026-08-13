import Foundation
import SharedKit

public enum AnnotationToolShortcut {
    private static let shortcuts: [String: AnnotationTool] = [
        "s": .select,
        "a": .arrow,
        "l": .line,
        "r": .rectangle,
        "e": .ellipse,
        "o": .ellipse,
        "t": .text,
        "d": .freehand,
        "f": .freehand,
        "p": .pixelate,
        "b": .pixelate,
        "c": .counter,
        "n": .counter,
        "h": .highlighter,
    ]

    private static let displayKeys: [AnnotationTool: String] = [
        .select: "S",
        .arrow: "A",
        .line: "L",
        .rectangle: "R",
        .ellipse: "E",
        .text: "T",
        .freehand: "D",
        .pixelate: "P",
        .counter: "C",
        .highlighter: "H",
    ]

    public static func tool(for key: String) -> AnnotationTool? {
        guard key.count == 1 else { return nil }
        return shortcuts[key.lowercased()]
    }

    /// Resolves a key press to a tool, except when Shift plus the center-lock
    /// extra key is held — that chord recenters a constrained drag instead.
    public static func tool(
        for key: String,
        keyCode: UInt16,
        shiftHeld: Bool,
        centerLockShortcut: SquareCenterLockShortcut
    ) -> AnnotationTool? {
        if centerLockShortcut.blocksToolShortcut(keyCode: keyCode, shiftHeld: shiftHeld) {
            return nil
        }
        return tool(for: key)
    }

    public static func displayKey(for tool: AnnotationTool) -> String? {
        displayKeys[tool]
    }

    public static func helpTitle(_ title: String, for tool: AnnotationTool) -> String {
        guard let key = displayKey(for: tool) else { return title }
        return "\(title) (\(key))"
    }
}
