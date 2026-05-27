import CoreGraphics
import Testing
@testable import RecordingKit

@Suite("RecordingVideoGeometry")
struct RecordingVideoGeometryTests {
    @Test("Uses actual 1x display scale without doubling")
    func dimensionsForOneXDisplay() {
        let dims = RecordingVideoGeometry.dimensions(
            for: CGRect(x: 0, y: 0, width: 863, height: 604),
            pointPixelScale: 1
        )

        #expect(dims == RecordingVideoDimensions(w: 864, h: 604))
    }

    @Test("Uses actual 2x display scale for Retina output")
    func dimensionsForTwoXDisplay() {
        let dims = RecordingVideoGeometry.dimensions(
            for: CGRect(x: 0, y: 0, width: 863, height: 604),
            pointPixelScale: 2
        )

        #expect(dims == RecordingVideoDimensions(w: 1726, h: 1208))
    }

    @Test("Rounds fractional scaled dimensions up to even encoder sizes")
    func dimensionsRoundUpToEvenSizes() {
        let dims = RecordingVideoGeometry.dimensions(
            for: CGRect(x: 0, y: 0, width: 863.5, height: 604.5),
            pointPixelScale: 2
        )

        #expect(dims == RecordingVideoDimensions(w: 1728, h: 1210))
    }

    @Test("Clamps invalid scale to 1x")
    func dimensionsClampScale() {
        let dims = RecordingVideoGeometry.dimensions(
            for: CGRect(x: 0, y: 0, width: 320, height: 241),
            pointPixelScale: 0
        )

        #expect(dims == RecordingVideoDimensions(w: 320, h: 242))
    }
}
