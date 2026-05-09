// Packages/AnnotationKit/Sources/AnnotationKit/Objects/ArrowObject.swift
import Foundation
import CoreGraphics

public final class ArrowObject: AnnotationObject, @unchecked Sendable {
    public let id = ObjectID()
    public var style: StrokeStyle
    public var start: CGPoint
    public var end: CGPoint
    public var controlPoint: CGPoint?
    public var headLength: CGFloat = 15

    public init(start: CGPoint, end: CGPoint, style: StrokeStyle = StrokeStyle()) {
        self.start = start
        self.end = end
        self.style = style
    }

    /// Arrowhead length scales with stroke width for visual consistency.
    private var effectiveHeadLength: CGFloat {
        max(headLength, style.lineWidth * 3)
    }

    public var bounds: CGRect {
        let hl = effectiveHeadLength
        let minX = min(start.x, end.x) - hl
        let minY = min(start.y, end.y) - hl
        let maxX = max(start.x, end.x) + hl
        let maxY = max(start.y, end.y) + hl
        if let controlPoint {
            return CGRect(
                x: min(minX, controlPoint.x - hl),
                y: min(minY, controlPoint.y - hl),
                width: max(maxX, controlPoint.x + hl) - min(minX, controlPoint.x - hl),
                height: max(maxY, controlPoint.y + hl) - min(minY, controlPoint.y - hl)
            )
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        if let controlPoint {
            return AnnotationGeometry.distanceToQuadraticCurve(
                point: point,
                start: start,
                control: controlPoint,
                end: end
            ) <= threshold + style.lineWidth / 2
        }

        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 0 else { return hypot(point.x - start.x, point.y - start.y) <= threshold }
        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSq
        t = max(0, min(1, t))
        let projX = start.x + t * dx
        let projY = start.y + t * dy
        let dist = hypot(point.x - projX, point.y - projY)
        return dist <= threshold + style.lineWidth / 2
    }

    public func render(in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setLineWidth(style.lineWidth)
        ctx.setAlpha(style.opacity)
        ctx.setLineCap(.round)
        style.pattern.apply(to: ctx, lineWidth: style.lineWidth)
        ctx.move(to: start)
        if let controlPoint {
            ctx.addQuadCurve(to: end, control: controlPoint)
        } else {
            ctx.addLine(to: end)
        }
        ctx.strokePath()

        ctx.setLineDash(phase: 0, lengths: [])
        let angle = AnnotationGeometry.curveEndAngle(start: start, control: controlPoint, end: end)
        let headAngle: CGFloat = .pi / 6
        let hl = effectiveHeadLength
        let p1 = CGPoint(x: end.x - hl * cos(angle - headAngle), y: end.y - hl * sin(angle - headAngle))
        let p2 = CGPoint(x: end.x - hl * cos(angle + headAngle), y: end.y - hl * sin(angle + headAngle))
        ctx.move(to: end); ctx.addLine(to: p1)
        ctx.move(to: end); ctx.addLine(to: p2)
        ctx.strokePath()
        ctx.restoreGState()
    }

    public func move(by delta: CGSize) {
        start.x += delta.width; start.y += delta.height
        end.x += delta.width; end.y += delta.height
        controlPoint?.x += delta.width
        controlPoint?.y += delta.height
    }

    public func copy() -> any AnnotationObject {
        let c = ArrowObject(start: start, end: end, style: style)
        c.controlPoint = controlPoint
        c.headLength = headLength
        return c
    }
}
