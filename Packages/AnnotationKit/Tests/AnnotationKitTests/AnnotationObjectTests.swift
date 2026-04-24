// Packages/AnnotationKit/Tests/AnnotationKitTests/AnnotationObjectTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import AnnotationKit

@Suite("AnnotationObject")
struct AnnotationObjectTests {
    @Test("AnnotationTool has all cases")
    func tools() {
        let tools: [AnnotationTool] = [.select, .arrow, .rectangle, .ellipse, .text, .freehand, .pixelate, .counter, .highlighter]
        #expect(tools.count == 9)
    }

    @Test("StrokeStyle has defaults")
    func strokeDefaults() {
        let style = StrokeStyle()
        #expect(style.color == .red)
        #expect(style.lineWidth == 3.0)
        #expect(style.opacity == 1.0)
    }

    @Test("ObjectID is unique")
    func uniqueIDs() {
        let id1 = ObjectID()
        let id2 = ObjectID()
        #expect(id1 != id2)
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
