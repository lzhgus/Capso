// Packages/AnnotationKit/Sources/AnnotationKit/AnnotationObject.swift
import Foundation
import CoreGraphics
import AppKit

public enum AnnotationTool: String, CaseIterable, Sendable {
    case select, arrow, rectangle, ellipse, text, freehand, pixelate, counter, highlighter
}

public struct ObjectID: Hashable, Sendable {
    public let value: UUID
    public init() { self.value = UUID() }
}

public struct StrokeStyle: Sendable {
    public var color: AnnotationColor
    public var lineWidth: CGFloat
    public var opacity: CGFloat
    public var filled: Bool

    public init(color: AnnotationColor = .red, lineWidth: CGFloat = 3, opacity: CGFloat = 1, filled: Bool = false) {
        self.color = color
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.filled = filled
    }
}

public enum AnnotationColor: String, CaseIterable, Sendable {
    case red, orange, yellow, green, blue, purple, white, black

    public var cgColor: CGColor {
        switch self {
        case .red: return CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)
        case .orange: return CGColor(red: 1, green: 0.58, blue: 0, alpha: 1)
        case .yellow: return CGColor(red: 1, green: 0.8, blue: 0, alpha: 1)
        case .green: return CGColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)
        case .blue: return CGColor(red: 0, green: 0.48, blue: 1, alpha: 1)
        case .purple: return CGColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1)
        case .white: return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        case .black: return CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        }
    }

    public var nsColor: NSColor { NSColor(cgColor: cgColor)! }
}

public protocol AnnotationObject: AnyObject, Sendable {
    var id: ObjectID { get }
    var style: StrokeStyle { get set }
    var bounds: CGRect { get }
    func hitTest(point: CGPoint, threshold: CGFloat) -> Bool
    func render(in context: CGContext)
    func move(by delta: CGSize)
    func copy() -> any AnnotationObject
}
