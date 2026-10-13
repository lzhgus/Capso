import AnnotationKit
import XCTest

@testable import Capso

final class AnnotationStylePresetTests: XCTestCase {
    func testPresetsSurviveSavingAndLoading() {
        let presets = [
            AnnotationStylePreset(tool: "arrow", color: .blue, lineWidth: 6, filled: false, pattern: .dashed,
                                  arrowHead: .tapered, textFill: false, textOutline: false, textStroke: true),
            AnnotationStylePreset(tool: "text", color: AnnotationColor(rawValue: "#12AB34")!, lineWidth: 36, filled: false,
                                  pattern: .solid, arrowHead: .standard, textFill: true, textOutline: true, textStroke: false),
        ]
        XCTAssertEqual(AnnotationStylePreset.decodeList(AnnotationStylePreset.encodeList(presets)), presets)
    }

    func testUnreadableDataGivesNoPresets() {
        XCTAssertEqual(AnnotationStylePreset.decodeList(Data("nope".utf8)), [])
        XCTAssertEqual(AnnotationStylePreset.decodeList(Data()), [])
    }

    func testTitleNamesToolAndWidth() {
        let preset = AnnotationStylePreset(tool: "rectangle", color: .red, lineWidth: 4.6, filled: true, pattern: .solid,
                                           arrowHead: .standard, textFill: false, textOutline: false, textStroke: true)
        XCTAssertEqual(preset.title, "Rectangle · 5 pt")
        XCTAssertEqual(AnnotationStylePreset(tool: "gone", color: .red, lineWidth: 1, filled: false, pattern: .solid,
                                             arrowHead: .standard, textFill: false, textOutline: false, textStroke: false).annotationTool, .arrow)
    }
}
