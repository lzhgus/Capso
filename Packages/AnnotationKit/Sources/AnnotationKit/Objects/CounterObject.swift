// Packages/AnnotationKit/Sources/AnnotationKit/Objects/CounterObject.swift
import Foundation
import CoreGraphics
import AppKit

public final class CounterObject: AnnotationObject, @unchecked Sendable {
    public let id = ObjectID()
    public var style: StrokeStyle
    public var center: CGPoint
    public var tip: CGPoint?
    public var radius: CGFloat
    public var number: Int

    public static let arrowClearance: CGFloat = 6

    public init(center: CGPoint, tip: CGPoint? = nil, number: Int, radius: CGFloat = 20, style: StrokeStyle = StrokeStyle()) {
        self.center = center
        self.tip = tip
        self.number = number
        self.radius = radius
        self.style = style
    }

    public var hasArrow: Bool {
        guard let tip else { return false }
        return hypot(tip.x - center.x, tip.y - center.y) >= radius + Self.arrowClearance
    }

    private var arrowLineWidth: CGFloat {
        max(2, min(style.lineWidth, radius * 0.28))
    }

    private var arrowHeadLength: CGFloat {
        max(10, arrowLineWidth * 3)
    }

    public var bounds: CGRect {
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        guard hasArrow, let tip else { return circle }
        return circle.union(CGRect(
            x: tip.x - arrowHeadLength,
            y: tip.y - arrowHeadLength,
            width: arrowHeadLength * 2,
            height: arrowHeadLength * 2
        ))
    }

    public func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        let distance = hypot(point.x - center.x, point.y - center.y)
        if distance <= radius + threshold {
            return true
        }
        guard hasArrow, let tip else { return false }
        return AnnotationGeometry.distanceToSegment(point: point, start: center, end: tip)
            <= threshold + arrowLineWidth / 2
    }

    public func render(in ctx: CGContext) {
        let circleRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        ctx.saveGState()
        if hasArrow, let tip {
            ctx.setStrokeColor(style.color.cgColor)
            ctx.setLineWidth(arrowLineWidth)
            ctx.setLineCap(.round)
            ctx.move(to: center)
            ctx.addLine(to: tip)
            ctx.strokePath()

            let angle = atan2(tip.y - center.y, tip.x - center.x)
            let headAngle: CGFloat = .pi / 6
            let hl = arrowHeadLength
            let p1 = CGPoint(
                x: tip.x - hl * cos(angle - headAngle),
                y: tip.y - hl * sin(angle - headAngle)
            )
            let p2 = CGPoint(
                x: tip.x - hl * cos(angle + headAngle),
                y: tip.y - hl * sin(angle + headAngle)
            )
            ctx.move(to: tip)
            ctx.addLine(to: p1)
            ctx.move(to: tip)
            ctx.addLine(to: p2)
            ctx.strokePath()
        }

        ctx.setFillColor(style.color.cgColor)
        ctx.fillEllipse(in: circleRect)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.25))
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: circleRect)
        ctx.restoreGState()

        let text = "\(number)" as NSString
        let fontSize: CGFloat = number < 10 ? radius * 1.1 : radius * 0.85
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let textOrigin = CGPoint(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2
        )

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        text.draw(at: textOrigin, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    public func move(by delta: CGSize) {
        center.x += delta.width
        center.y += delta.height
        tip?.x += delta.width
        tip?.y += delta.height
    }

    public func copy() -> any AnnotationObject {
        CounterObject(center: center, tip: tip, number: number, radius: radius, style: style)
    }
}
