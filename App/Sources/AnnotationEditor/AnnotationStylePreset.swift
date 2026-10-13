import AppKit
import AnnotationKit

/// A saved combination of tool and style the user can switch back to in one click.
struct AnnotationStylePreset: Codable, Hashable, Identifiable {
    var id = UUID()
    var tool: String
    var color: AnnotationColor
    var lineWidth: Double
    var filled: Bool
    var pattern: StrokePattern
    var arrowHead: ArrowHeadStyle
    var textFill: Bool
    var textOutline: Bool
    var textStroke: Bool

    var annotationTool: AnnotationTool { AnnotationTool(rawValue: tool) ?? .arrow }

    var title: String {
        "\(annotationTool.localizedToolName) · \(Int(lineWidth.rounded())) pt"
    }

    var swatch: NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            NSColor(cgColor: color.cgColor)?.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
    }

    static func decodeList(_ data: Data) -> [AnnotationStylePreset] {
        (try? JSONDecoder().decode([AnnotationStylePreset].self, from: data)) ?? []
    }

    static func encodeList(_ presets: [AnnotationStylePreset]) -> Data {
        (try? JSONEncoder().encode(presets)) ?? Data()
    }
}
