import Testing
import Foundation
import CoreGraphics
@testable import AnnotationKit

@Suite("AnnotationDragConstraint")
struct AnnotationDragConstraintTests {
    private let start = CGPoint(x: 100, y: 100)

    // MARK: - Tool mapping

    @Test("Box tools lock to a square")
    func squareTools() {
        for tool in [AnnotationTool.rectangle, .ellipse, .pixelate] {
            #expect(AnnotationDragConstraint.kind(for: tool) == .square)
        }
    }

    @Test("Line-like tools snap by angle")
    func angleTools() {
        for tool in [AnnotationTool.arrow, .line] {
            #expect(AnnotationDragConstraint.kind(for: tool) == .angle)
        }
    }

    @Test("Freehand, text, counter and select are unconstrained")
    func unconstrainedTools() {
        for tool in [AnnotationTool.select, .text, .freehand, .highlighter, .counter] {
            #expect(AnnotationDragConstraint.kind(for: tool) == .none)
            let end = CGPoint(x: 260, y: 140)
            #expect(AnnotationDragConstraint.constrainedEnd(from: start, to: end, tool: tool) == end)
        }
    }

    // MARK: - Square lock

    @Test("The larger axis sets the side length")
    func squareUsesLargerAxis() {
        let end = AnnotationDragConstraint.squaredEnd(from: start, to: CGPoint(x: 260, y: 140))
        #expect(end == CGPoint(x: 260, y: 260))
    }

    @Test("A square drag keeps each axis direction")
    func squarePreservesDirection() {
        let upLeft = AnnotationDragConstraint.squaredEnd(from: start, to: CGPoint(x: 20, y: 60))
        #expect(upLeft == CGPoint(x: 20, y: 20))

        let downLeft = AnnotationDragConstraint.squaredEnd(from: start, to: CGPoint(x: 40, y: 130))
        #expect(downLeft == CGPoint(x: 40, y: 160))
    }

    @Test("A square drag with no movement stays at the anchor")
    func squareWithoutMovement() {
        #expect(AnnotationDragConstraint.squaredEnd(from: start, to: start) == start)
    }

    @Test("Squaring a rectangle drag produces equal width and height")
    func squaredRectIsSquare() {
        let end = AnnotationDragConstraint.constrainedEnd(
            from: start,
            to: CGPoint(x: 340, y: 190),
            tool: .rectangle
        )
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        #expect(rect.width == rect.height)
        #expect(rect == CGRect(x: 100, y: 100, width: 240, height: 240))
    }

    // MARK: - Angle snap

    @Test("A near-horizontal drag snaps flat and keeps its length")
    func angleSnapsToHorizontal() {
        let end = AnnotationDragConstraint.angleSnappedEnd(from: start, to: CGPoint(x: 300, y: 112))
        let length = hypot(300 - start.x, 112 - start.y)

        #expect(abs(end.y - start.y) < 0.0001)
        #expect(abs(end.x - (start.x + length)) < 0.0001)
    }

    @Test("A near-vertical drag snaps upright")
    func angleSnapsToVertical() {
        let end = AnnotationDragConstraint.angleSnappedEnd(from: start, to: CGPoint(x: 108, y: 320))

        #expect(abs(end.x - start.x) < 0.0001)
        #expect(end.y > start.y)
    }

    @Test("A drag near 45° snaps to an exact diagonal")
    func angleSnapsToDiagonal() {
        let end = AnnotationDragConstraint.angleSnappedEnd(from: start, to: CGPoint(x: 200, y: 190))
        let dx = end.x - start.x
        let dy = end.y - start.y

        #expect(abs(dx - dy) < 0.0001)
        #expect(dx > 0)
    }

    @Test("Angle snapping preserves the drag length on every increment")
    func angleSnapPreservesLength() {
        for degrees in stride(from: 0, to: 360, by: 7) {
            let radians = CGFloat(degrees) * .pi / 180
            let raw = CGPoint(x: start.x + cos(radians) * 150, y: start.y + sin(radians) * 150)
            let snapped = AnnotationDragConstraint.angleSnappedEnd(from: start, to: raw)
            let length = hypot(snapped.x - start.x, snapped.y - start.y)

            #expect(abs(length - 150) < 0.0001, "length drifted at \(degrees)°")
        }
    }

    @Test("Angle snapping never moves the endpoint more than 22.5°")
    func angleSnapStaysWithinHalfIncrement() {
        for degrees in stride(from: 0, to: 360, by: 3) {
            let radians = CGFloat(degrees) * .pi / 180
            let raw = CGPoint(x: start.x + cos(radians) * 150, y: start.y + sin(radians) * 150)
            let snapped = AnnotationDragConstraint.angleSnappedEnd(from: start, to: raw)
            let snappedAngle = atan2(snapped.y - start.y, snapped.x - start.x)

            var delta = abs(snappedAngle - radians)
            if delta > .pi { delta = 2 * .pi - delta }

            #expect(delta <= .pi / 8 + 0.0001, "snapped too far at \(degrees)°")
        }
    }

    @Test("A zero-length drag is left alone")
    func angleSnapWithoutMovement() {
        #expect(AnnotationDragConstraint.angleSnappedEnd(from: start, to: start) == start)
    }
}
