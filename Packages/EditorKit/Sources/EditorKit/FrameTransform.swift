// Packages/EditorKit/Sources/EditorKit/FrameTransform.swift

import Foundation

/// A 2D scale + translate transform applied to a video frame during compositing.
///
/// All values are in normalized coordinates unless otherwise noted.
/// `scale` > 1.0 zooms in; translations shift the visible crop window.
public struct FrameTransform: Sendable, Equatable {
    /// Uniform scale factor. 1.0 = no zoom.
    public var scale: Double
    /// Horizontal translation. 0 = centered.
    public var translateX: Double
    /// Vertical translation. 0 = centered.
    public var translateY: Double

    public init(scale: Double = 1.0, translateX: Double = 0.0, translateY: Double = 0.0) {
        self.scale = scale
        self.translateX = translateX
        self.translateY = translateY
    }

    /// No-op transform: no zoom, no translation.
    public static let identity = FrameTransform()
}
