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
        ctx.setFillColor(style.color.cgColor)
        ctx.setLineWidth(style.lineWidth)
        ctx.setAlpha(style.opacity)
        let hl = effectiveHeadLength
        let endAngle = AnnotationGeometry.curveEndAngle(start: start, control: controlPoint, end: end)

        switch style.arrowHead {
        case .standard:
            strokeShaft(in: ctx, cap: .round)
            ctx.setLineDash(phase: 0, lengths: [])
            let (p1, p2) = headCorners(tip: end, angle: endAngle, length: hl, spread: .pi / 6)
            ctx.move(to: end); ctx.addLine(to: p1)
            ctx.move(to: end); ctx.addLine(to: p2)
            ctx.strokePath()
        case .filled, .double:
            let headLength = hl * 1.2
            let trim = headLength * 0.8
            strokeShaft(in: ctx, cap: .butt, trimStart: style.arrowHead == .double ? trim : 0, trimEnd: trim)
            fillHead(in: ctx, tip: end, angle: endAngle, length: headLength)
            if style.arrowHead == .double {
                let startAngle = AnnotationGeometry.curveEndAngle(start: end, control: controlPoint, end: start)
                fillHead(in: ctx, tip: start, angle: startAngle, length: headLength)
            }
        case .tapered:
            fillTaperedShaft(in: ctx, headLength: hl * 1.3)
            fillHead(in: ctx, tip: end, angle: endAngle, length: hl * 1.3)
        }
        ctx.restoreGState()
    }

    private func strokeShaft(in ctx: CGContext, cap: CGLineCap, trimStart: CGFloat = 0, trimEnd: CGFloat = 0) {
        ctx.setLineCap(cap)
        style.pattern.apply(to: ctx, lineWidth: style.lineWidth)
        if trimStart == 0 && trimEnd == 0 {
            ctx.move(to: start)
            if let controlPoint {
                ctx.addQuadCurve(to: end, control: controlPoint)
            } else {
                ctx.addLine(to: end)
            }
        } else {
            ctx.addLines(between: shaftPoints(trimStart: trimStart, trimEnd: trimEnd))
        }
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
    }

    /// The shaft as a polyline, shortened by `trimStart` / `trimEnd` along its length
    /// so it ends at the base of a solid head instead of poking through its tip.
    private func shaftPoints(trimStart: CGFloat, trimEnd: CGFloat) -> [CGPoint] {
        let points = AnnotationGeometry.curvePoints(start: start, control: controlPoint, end: end, count: controlPoint == nil ? 1 : 32)
        var lengths: [CGFloat] = [0]
        for (a, b) in zip(points, points.dropFirst()) { lengths.append(lengths.last! + hypot(b.x - a.x, b.y - a.y)) }
        let total = lengths.last!
        let from = min(trimStart, total / 2), to = max(total - trimEnd, from)
        func point(at distance: CGFloat) -> CGPoint {
            guard let i = lengths.firstIndex(where: { $0 >= distance }), i > 0 else { return points[0] }
            let t = (distance - lengths[i - 1]) / max(lengths[i] - lengths[i - 1], .ulpOfOne)
            return CGPoint(x: points[i - 1].x + (points[i].x - points[i - 1].x) * t,
                           y: points[i - 1].y + (points[i].y - points[i - 1].y) * t)
        }
        let inner = zip(points, lengths).filter { $0.1 > from && $0.1 < to }.map(\.0)
        return [point(at: from)] + inner + [point(at: to)]
    }

    private func headCorners(tip: CGPoint, angle: CGFloat, length: CGFloat, spread: CGFloat) -> (CGPoint, CGPoint) {
        (CGPoint(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread)),
         CGPoint(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread)))
    }

    private func fillHead(in ctx: CGContext, tip: CGPoint, angle: CGFloat, length: CGFloat) {
        let (p1, p2) = headCorners(tip: tip, angle: angle, length: length, spread: .pi / 7)
        ctx.move(to: tip)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
    }

    /// A filled outline that is thin at the tail and as wide as the stroke near the head.
    private func fillTaperedShaft(in ctx: CGContext, headLength: CGFloat) {
        let points = shaftPoints(trimStart: 0, trimEnd: headLength * 0.8)
        let total = zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        guard total > 0 else { return }
        var left: [CGPoint] = [], right: [CGPoint] = []
        var travelled: CGFloat = 0
        for (i, p) in points.enumerated() {
            if i > 0 { travelled += hypot(p.x - points[i - 1].x, p.y - points[i - 1].y) }
            let a = points[max(i - 1, 0)], b = points[min(i + 1, points.count - 1)]
            let angle = atan2(b.y - a.y, b.x - a.x)
            let progress = min(travelled / max(total, 1), 1)
            let half = style.lineWidth * (0.15 + 0.85 * progress)
            left.append(CGPoint(x: p.x - half * sin(angle), y: p.y + half * cos(angle)))
            right.append(CGPoint(x: p.x + half * sin(angle), y: p.y - half * cos(angle)))
        }
        ctx.addLines(between: left + right.reversed())
        ctx.closePath()
        ctx.fillPath()
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
