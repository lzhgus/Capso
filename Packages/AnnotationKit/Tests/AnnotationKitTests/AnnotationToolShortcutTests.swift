import Testing
@testable import AnnotationKit

@Suite("AnnotationToolShortcut")
struct AnnotationToolShortcutTests {
    @Test("maps requested annotation tool shortcuts")
    func mapsRequestedToolShortcuts() {
        #expect(AnnotationToolShortcut.tool(for: "s") == .select)
        #expect(AnnotationToolShortcut.tool(for: "a") == .arrow)
        #expect(AnnotationToolShortcut.tool(for: "t") == .text)
        #expect(AnnotationToolShortcut.tool(for: "l") == .line)
    }

    @Test("maps every annotation tool to at least one shortcut")
    func mapsEveryTool() {
        let shortcuts: [String: AnnotationTool] = [
            "s": .select,
            "a": .arrow,
            "l": .line,
            "r": .rectangle,
            "e": .ellipse,
            "t": .text,
            "d": .freehand,
            "p": .pixelate,
            "c": .counter,
            "h": .highlighter,
        ]

        for (key, tool) in shortcuts {
            #expect(AnnotationToolShortcut.tool(for: key) == tool)
            #expect(AnnotationToolShortcut.displayKey(for: tool) != nil)
        }
    }

    @Test("supports intuitive aliases")
    func supportsAliases() {
        #expect(AnnotationToolShortcut.tool(for: "o") == .ellipse)
        #expect(AnnotationToolShortcut.tool(for: "f") == .freehand)
        #expect(AnnotationToolShortcut.tool(for: "b") == .pixelate)
        #expect(AnnotationToolShortcut.tool(for: "n") == .counter)
    }

    @Test("formats discoverable help titles with shortcut keys")
    func formatsHelpTitlesWithShortcutKeys() {
        #expect(AnnotationToolShortcut.helpTitle("Arrow", for: .arrow) == "Arrow (A)")
        #expect(AnnotationToolShortcut.helpTitle("Pixelate / Blur", for: .pixelate) == "Pixelate / Blur (P)")
    }

    @Test("is case insensitive and ignores unknown keys")
    func handlesCaseAndUnknownKeys() {
        #expect(AnnotationToolShortcut.tool(for: "A") == .arrow)
        #expect(AnnotationToolShortcut.tool(for: " ") == nil)
        #expect(AnnotationToolShortcut.tool(for: "save") == nil)
    }
}
