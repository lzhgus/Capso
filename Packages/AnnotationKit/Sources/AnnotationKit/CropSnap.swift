import Foundation
import CoreGraphics

public enum CropSnap {
    /// Snap `value` to the closest target in `toEdges` if within `threshold`.
    /// Returns the original value if no target is close enough or if threshold <= 0.
    public static func snap(value: CGFloat, toEdges edges: [CGFloat], threshold: CGFloat) -> CGFloat {
        guard threshold > 0 else { return value }
        var best = value
        var bestDist = threshold
        for edge in edges {
            let d = abs(value - edge)
            if d <= bestDist {
                bestDist = d
                best = edge
            }
        }
        return best
    }

    /// Snap a crop rectangle's four edges to the image bounds (0/width on X, 0/height on Y)
    /// when they are within `threshold`. Threshold is in image pixels. Pass 0 to disable.
    public static func snapRect(_ rect: CGRect, to imageSize: CGSize, threshold: CGFloat) -> CGRect {
        guard threshold > 0 else { return rect }
        let xEdges: [CGFloat] = [0, imageSize.width]
        let yEdges: [CGFloat] = [0, imageSize.height]

        let minX = snap(value: rect.minX, toEdges: xEdges, threshold: threshold)
        let maxX = snap(value: rect.maxX, toEdges: xEdges, threshold: threshold)
        let minY = snap(value: rect.minY, toEdges: yEdges, threshold: threshold)
        let maxY = snap(value: rect.maxY, toEdges: yEdges, threshold: threshold)

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
