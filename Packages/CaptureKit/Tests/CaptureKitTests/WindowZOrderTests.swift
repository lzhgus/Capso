import CoreGraphics
import Testing
@testable import CaptureKit

@Suite("Window z-order")
struct WindowZOrderTests {
    @Test("Reorders windows to match the system front-to-back order")
    func reordersToMatchZOrder() {
        let ordered = ContentEnumerator.orderedFrontToBack(
            [CGWindowID(10), 20, 30],
            id: { $0 },
            zOrder: [30, 10, 20]
        )
        #expect(ordered == [30, 10, 20])
    }

    @Test("Keeps windows missing from the z-order after known ones, in original order")
    func unknownWindowsGoLast() {
        let ordered = ContentEnumerator.orderedFrontToBack(
            [CGWindowID(1), 2, 3, 4],
            id: { $0 },
            zOrder: [3, 1]
        )
        #expect(ordered == [3, 1, 2, 4])
    }

    @Test("Leaves order unchanged when the z-order is unavailable")
    func emptyZOrderIsNoOp() {
        let ordered = ContentEnumerator.orderedFrontToBack(
            [CGWindowID(5), 4, 6],
            id: { $0 },
            zOrder: []
        )
        #expect(ordered == [5, 4, 6])
    }
}
