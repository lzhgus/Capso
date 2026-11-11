import AppKit
import XCTest
@testable import Capso

@MainActor
final class WindowDragGeometryTests: XCTestCase {
    /// SwiftUI reports the downward part of a drag as a positive height, while an
    /// `NSWindow` origin grows upward. Dragging the card down must therefore
    /// lower the origin, or the card would move away from the pointer.
    func testDragDownLowersWindowOrigin() {
        let start = NSPoint(x: 100, y: 500)

        let moved = WindowDragGeometry.origin(
            start: start,
            translation: CGSize(width: 40, height: 60)
        )

        XCTAssertEqual(moved.x, 140, accuracy: 0.001)
        XCTAssertEqual(moved.y, 440, accuracy: 0.001)
    }

    func testDragUpRaisesWindowOrigin() {
        let start = NSPoint(x: 100, y: 500)

        let moved = WindowDragGeometry.origin(
            start: start,
            translation: CGSize(width: -30, height: -25)
        )

        XCTAssertEqual(moved.x, 70, accuracy: 0.001)
        XCTAssertEqual(moved.y, 525, accuracy: 0.001)
    }

    /// A drag that has not moved yet (the gesture's first callback) must leave
    /// the card exactly where it was.
    func testZeroTranslationKeepsOrigin() {
        let start = NSPoint(x: 12.5, y: -80)

        let moved = WindowDragGeometry.origin(start: start, translation: .zero)

        XCTAssertEqual(moved, start)
    }
}
