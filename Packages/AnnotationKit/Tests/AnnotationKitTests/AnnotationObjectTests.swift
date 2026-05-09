// Packages/AnnotationKit/Tests/AnnotationKitTests/AnnotationObjectTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import AnnotationKit

@Suite("AnnotationObject")
struct AnnotationObjectTests {
    @Test("AnnotationTool has all cases")
    func tools() {
        let tools: [AnnotationTool] = [.select, .arrow, .line, .rectangle, .ellipse, .text, .freehand, .pixelate, .counter, .highlighter]
        #expect(tools.count == 10)
    }

    @Test("StrokeStyle has defaults")
    func strokeDefaults() {
        let style = StrokeStyle()
        #expect(style.color == .red)
        #expect(style.lineWidth == 3.0)
        #expect(style.opacity == 1.0)
        #expect(style.pattern == .solid)
    }

    @Test("StrokeStyle stores non-solid line patterns")
    func strokePatterns() {
        let dashed = StrokeStyle(pattern: .dashed)
        let dotted = StrokeStyle(pattern: .dotted)

        #expect(StrokePattern.allCases == [.solid, .dashed, .dotted])
        #expect(dashed.pattern == .dashed)
        #expect(dotted.pattern == .dotted)
    }

    @Test("AnnotationColor keeps preset raw values")
    func presetColorRawValues() {
        #expect(AnnotationColor(rawValue: "red") == .red)
        #expect(AnnotationColor.blue.rawValue == "blue")
        #expect(AnnotationColor.allCases.contains(.purple))
    }

    @Test("AnnotationColor supports custom hex colors")
    func customHexColor() {
        let color = AnnotationColor(rawValue: "#3366CC")
        #expect(color?.rawValue == "#3366CC")
        #expect(color?.hexRGB == "#3366CC")

        let components = color?.cgColor.components
        #expect(components?[0] == 0.2)
        #expect(components?[1] == 0.4)
        #expect(components?[2] == 0.8)
        #expect(components?[3] == 1.0)
    }

    @Test("ObjectID is unique")
    func uniqueIDs() {
        let id1 = ObjectID()
        let id2 = ObjectID()
        #expect(id1 != id2)
    }
}

@Suite("LineObject")
struct LineObjectTests {
    @Test("Line has bounds padded by stroke width")
    func bounds() {
        let line = LineObject(
            start: CGPoint(x: 10, y: 20),
            end: CGPoint(x: 110, y: 70),
            style: StrokeStyle(lineWidth: 6)
        )
        let b = line.bounds
        #expect(b.minX <= 10)
        #expect(b.minY <= 20)
        #expect(b.maxX >= 110)
        #expect(b.maxY >= 70)
    }

    @Test("Line hit test follows the segment")
    func hitTest() {
        let line = LineObject(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
        #expect(line.hitTest(point: CGPoint(x: 50, y: 0), threshold: 5))
        #expect(!line.hitTest(point: CGPoint(x: 50, y: 20), threshold: 5))
    }

    @Test("Line move keeps endpoints together")
    func move() {
        let line = LineObject(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 50))
        line.move(by: CGSize(width: 5, height: 5))
        #expect(line.start == CGPoint(x: 15, y: 15))
        #expect(line.end == CGPoint(x: 55, y: 55))
    }

    @Test("Line control point bends hit testing and travels with the line")
    func controlPointBendsLine() {
        let line = LineObject(
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 100, y: 0),
            style: StrokeStyle(lineWidth: 4)
        )
        line.controlPoint = CGPoint(x: 50, y: 80)

        #expect(line.bounds.contains(CGPoint(x: 50, y: 80)))
        #expect(line.hitTest(point: CGPoint(x: 50, y: 40), threshold: 4))
        #expect(!line.hitTest(point: CGPoint(x: 50, y: 0), threshold: 4))

        line.move(by: CGSize(width: 10, height: -5))
        #expect(line.start == CGPoint(x: 10, y: -5))
        #expect(line.end == CGPoint(x: 110, y: -5))
        #expect(line.controlPoint == CGPoint(x: 60, y: 75))
    }

    @Test("Line copy preserves bend state")
    func copyPreservesControlPoint() {
        let line = LineObject(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
        line.controlPoint = CGPoint(x: 40, y: 60)
        line.style.pattern = .dashed

        let copy = line.copy() as? LineObject

        #expect(copy?.start == line.start)
        #expect(copy?.end == line.end)
        #expect(copy?.controlPoint == line.controlPoint)
        #expect(copy?.style.pattern == .dashed)
    }
}

@Suite("ArrowObject")
struct ArrowObjectTests {
    @Test("Arrow has correct bounds")
    func bounds() {
        let arrow = ArrowObject(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 110, y: 70))
        let b = arrow.bounds
        #expect(b.minX <= 10)
        #expect(b.minY <= 20)
        #expect(b.maxX >= 110)
        #expect(b.maxY >= 70)
    }

    @Test("Arrow hit test on line")
    func hitTest() {
        let arrow = ArrowObject(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
        #expect(arrow.hitTest(point: CGPoint(x: 50, y: 0), threshold: 5))
        #expect(!arrow.hitTest(point: CGPoint(x: 50, y: 20), threshold: 5))
    }

    @Test("Arrow move")
    func move() {
        let arrow = ArrowObject(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 50))
        arrow.move(by: CGSize(width: 5, height: 5))
        #expect(arrow.start == CGPoint(x: 15, y: 15))
        #expect(arrow.end == CGPoint(x: 55, y: 55))
    }

    @Test("Arrow control point bends hit testing and travels with the arrow")
    func controlPointBendsArrow() {
        let arrow = ArrowObject(
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 100, y: 0),
            style: StrokeStyle(lineWidth: 4)
        )
        arrow.controlPoint = CGPoint(x: 50, y: 80)

        #expect(arrow.bounds.contains(CGPoint(x: 50, y: 80)))
        #expect(arrow.hitTest(point: CGPoint(x: 50, y: 40), threshold: 4))
        #expect(!arrow.hitTest(point: CGPoint(x: 50, y: 0), threshold: 4))

        arrow.move(by: CGSize(width: 10, height: -5))
        #expect(arrow.start == CGPoint(x: 10, y: -5))
        #expect(arrow.end == CGPoint(x: 110, y: -5))
        #expect(arrow.controlPoint == CGPoint(x: 60, y: 75))
    }

    @Test("Arrow copy preserves bend and stroke pattern")
    func copyPreservesControlPoint() {
        let arrow = ArrowObject(
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 100, y: 0),
            style: StrokeStyle(pattern: .dotted)
        )
        arrow.controlPoint = CGPoint(x: 60, y: 40)

        let copy = arrow.copy() as? ArrowObject

        #expect(copy?.start == arrow.start)
        #expect(copy?.end == arrow.end)
        #expect(copy?.controlPoint == arrow.controlPoint)
        #expect(copy?.style.pattern == .dotted)
    }
}

@Suite("RectangleObject")
struct RectangleObjectTests {
    @Test("Rectangle bounds match rect")
    func bounds() {
        let rect = RectangleObject(rect: CGRect(x: 10, y: 20, width: 100, height: 50))
        #expect(rect.bounds == CGRect(x: 10, y: 20, width: 100, height: 50))
    }

    @Test("Rectangle hit test on border")
    func hitTest() {
        let rect = RectangleObject(rect: CGRect(x: 10, y: 10, width: 100, height: 100))
        #expect(rect.hitTest(point: CGPoint(x: 10, y: 50), threshold: 5))
        #expect(!rect.hitTest(point: CGPoint(x: 200, y: 200), threshold: 5))
    }
}

@Suite("EllipseObject")
struct EllipseObjectTests {
    @Test("Ellipse bounds match rect")
    func bounds() {
        let ellipse = EllipseObject(rect: CGRect(x: 10, y: 20, width: 100, height: 50))
        #expect(ellipse.bounds == CGRect(x: 10, y: 20, width: 100, height: 50))
    }
}
