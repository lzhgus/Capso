import CoreGraphics
import Foundation

enum AnnotationGeometry {
    static func distanceToQuadraticCurve(
        point: CGPoint,
        start: CGPoint,
        control: CGPoint,
        end: CGPoint
    ) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        var previous = start

        for i in 1...32 {
            let t = CGFloat(i) / 32
            let current = quadraticPoint(t: t, start: start, control: control, end: end)
            best = min(best, distanceToSegment(point: point, start: previous, end: current))
            previous = current
        }

        return best
    }

    static func quadraticPoint(
        t: CGFloat,
        start: CGPoint,
        control: CGPoint,
        end: CGPoint
    ) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }

    static func distanceToSegment(point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 0 else { return hypot(point.x - start.x, point.y - start.y) }

        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSq
        t = max(0, min(1, t))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    static func curveEndAngle(start: CGPoint, control: CGPoint?, end: CGPoint) -> CGFloat {
        if let control, hypot(end.x - control.x, end.y - control.y) > 0 {
            return atan2(end.y - control.y, end.x - control.x)
        }
        return atan2(end.y - start.y, end.x - start.x)
    }
}
