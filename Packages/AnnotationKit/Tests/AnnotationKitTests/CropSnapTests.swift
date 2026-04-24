import Testing
import Foundation
import CoreGraphics
@testable import AnnotationKit

@Suite("CropSnap")
struct CropSnapTests {
    private let imageSize = CGSize(width: 1000, height: 800)

    @Test("Value within threshold of left edge snaps to 0")
    func snapToLeftEdge() {
        let snapped = CropSnap.snap(value: 5, toEdges: [0, 1000], threshold: 8)
        #expect(snapped == 0)
    }

    @Test("Value within threshold of right edge snaps to 1000")
    func snapToRightEdge() {
        let snapped = CropSnap.snap(value: 995, toEdges: [0, 1000], threshold: 8)
        #expect(snapped == 1000)
    }

    @Test("Value outside threshold stays unchanged")
    func noSnapOutsideThreshold() {
        let snapped = CropSnap.snap(value: 500, toEdges: [0, 1000], threshold: 8)
        #expect(snapped == 500)
    }

    @Test("Snap rect snaps all four edges to image bounds")
    func snapRectEdges() {
        let rect = CGRect(x: 5, y: 3, width: 992, height: 794)
        let snapped = CropSnap.snapRect(rect, to: imageSize, threshold: 8)
        #expect(snapped == CGRect(x: 0, y: 0, width: 1000, height: 800))
    }

    @Test("Snap rect leaves rect alone when far from edges")
    func snapRectFarFromEdges() {
        let rect = CGRect(x: 100, y: 100, width: 500, height: 400)
        let snapped = CropSnap.snapRect(rect, to: imageSize, threshold: 8)
        #expect(snapped == rect)
    }

    @Test("Threshold of 0 disables snapping")
    func zeroThresholdDisablesSnap() {
        let rect = CGRect(x: 1, y: 1, width: 998, height: 798)
        let snapped = CropSnap.snapRect(rect, to: imageSize, threshold: 0)
        #expect(snapped == rect)
    }
}
