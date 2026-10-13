// Packages/AnnotationKit/Sources/AnnotationKit/Objects/SpotlightObject.swift
import Foundation
import CoreGraphics

/// Keeps an area bright while everything outside every spotlight is dimmed.
/// The dimming is drawn once for all spotlights by `renderDim`, so several
/// spotlights share one shade instead of stacking.
public final class SpotlightObject: AnnotationObject, @unchecked Sendable {
    public static let dimOpacity: CGFloat = 0.55
    public static let cornerRadius: CGFloat = 8

    public let id = ObjectID()
    public var style: StrokeStyle
    public var rect: CGRect

    public init(rect: CGRect, style: StrokeStyle = StrokeStyle()) {
        self.rect = rect
        self.style = style
    }

    public var bounds: CGRect { rect }

    public func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        rect.insetBy(dx: -threshold, dy: -threshold).contains(point)
    }

    /// Drawn by `renderDim` instead.
    public func render(in ctx: CGContext) {}

    public func move(by delta: CGSize) {
        rect.origin.x += delta.width; rect.origin.y += delta.height
    }

    public func copy() -> any AnnotationObject {
        SpotlightObject(rect: rect, style: style)
    }

    /// Dims `canvas` except inside every spotlight among `objects` (plus `extra`, e.g. one being drawn).
    public static func renderDim(for objects: [any AnnotationObject], extra: CGRect? = nil, canvas: CGRect, in ctx: CGContext) {
        let holes = objects.compactMap { ($0 as? SpotlightObject)?.rect } + (extra.map { [$0] } ?? [])
        guard !holes.isEmpty else { return }
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(CGColor(gray: 0, alpha: dimOpacity))
        ctx.fill(canvas)
        ctx.setBlendMode(.clear)
        for hole in holes {
            ctx.addPath(CGPath(roundedRect: hole, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            ctx.fillPath()
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
