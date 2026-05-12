// Packages/AnnotationKit/Tests/AnnotationKitTests/AnnotationObjectTests.swift
import Testing
import Foundation
import CoreGraphics
import AppKit
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

@Suite("TextObject")
struct TextObjectTests {
    @Test("Text copy preserves text effect colors")
    func copyPreservesTextEffectColors() {
        let text = TextObject(
            text: "Hello",
            origin: CGPoint(x: 10, y: 20),
            boxSize: CGSize(width: 120, height: 40),
            fillColor: .black,
            outlineColor: .white,
            glyphStrokeColor: .white
        )

        let copy = text.copy() as? TextObject

        #expect(copy?.text == text.text)
        #expect(copy?.origin == text.origin)
        #expect(copy?.boxSize == CGSize(width: 120, height: 40))
        #expect(copy?.fillColor == .black)
        #expect(copy?.outlineColor == .white)
        #expect(copy?.glyphStrokeColor == .white)
    }

    @Test("Text trace expands bounds enough for large glyph stroke")
    func traceExpandsBoundsEnoughForLargeGlyphStroke() {
        let text = TextObject(
            text: "Trace",
            origin: CGPoint(x: 20, y: 30),
            boxSize: CGSize(width: 100, height: 40),
            fontSize: 200,
            glyphStrokeColor: .white
        )

        #expect(text.bounds == CGRect(x: 14, y: 24, width: 112, height: 52))
    }

    @Test("Text trace preserves the foreground color")
    func tracePreservesForegroundColor() {
        let text = TextObject(
            text: "傅师大发生的",
            origin: CGPoint(x: 20, y: 20),
            boxSize: CGSize(width: 380, height: 96),
            fontSize: 72,
            glyphStrokeColor: .white,
            style: StrokeStyle(color: .yellow)
        )

        let counts = renderColorCounts(text)

        #expect(counts.yellow > counts.white)
    }

    @Test("Resize geometry scales text from bottom right while anchoring top left")
    func resizeGeometryScalesFromBottomRight() {
        let originalBounds = CGRect(x: 10, y: 20, width: 100, height: 50)

        let fontSize = TextResizeGeometry.fontSize(
            originalBounds: originalBounds,
            originalFontSize: 20,
            handle: .bottomRight,
            dragDelta: CGSize(width: 50, height: 10)
        )
        let origin = TextResizeGeometry.origin(
            originalBounds: originalBounds,
            resizedSize: CGSize(width: 150, height: 75),
            handle: .bottomRight
        )

        #expect(fontSize == 30)
        #expect(origin == CGPoint(x: 10, y: 20))
    }

    @Test("Resize geometry keeps the opposite corner anchored")
    func resizeGeometryKeepsOppositeCornerAnchored() {
        let originalBounds = CGRect(x: 10, y: 20, width: 100, height: 50)

        let origin = TextResizeGeometry.origin(
            originalBounds: originalBounds,
            resizedSize: CGSize(width: 150, height: 75),
            handle: .topLeft
        )

        #expect(origin == CGPoint(x: -40, y: -5))
    }

    @Test("Resize geometry changes text box while preserving opposite edge")
    func resizeGeometryChangesTextBox() {
        let originalBounds = CGRect(x: 10, y: 20, width: 100, height: 50)

        let rect = TextResizeGeometry.rect(
            originalBounds: originalBounds,
            handle: .topLeft,
            dragDelta: CGSize(width: 20, height: 10),
            minSize: CGSize(width: 60, height: 30)
        )

        #expect(rect == CGRect(x: 30, y: 30, width: 80, height: 40))
    }

    private func renderColorCounts(_ text: TextObject) -> (yellow: Int, white: Int) {
        let width = 420
        let height = 140
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * bytesPerPixel,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            Issue.record("Could not create bitmap context")
            return (0, 0)
        }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        text.render(in: context)

        var yellow = 0
        var white = 0
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let r = pixels[index]
            let g = pixels[index + 1]
            let b = pixels[index + 2]
            let a = pixels[index + 3]
            guard a > 0 else { continue }

            if r > 180, g > 140, b < 80 {
                yellow += 1
            } else if r > 180, g > 180, b > 180 {
                white += 1
            }
        }

        return (yellow, white)
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
