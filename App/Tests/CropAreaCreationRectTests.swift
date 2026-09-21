import CoreGraphics
import XCTest
@testable import Capso

@MainActor
final class CropAreaCreationRectTests: XCTestCase {
    func testDragDownRightProducesRectFromStart() {
        let rect = CropAreaNSView.creationRect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 110, y: 70), aspectRatio: nil)
        XCTAssertEqual(rect, CGRect(x: 10, y: 20, width: 100, height: 50))
    }

    func testDragUpLeftIsNormalised() {
        let rect = CropAreaNSView.creationRect(from: CGPoint(x: 110, y: 70), to: CGPoint(x: 10, y: 20), aspectRatio: nil)
        XCTAssertEqual(rect, CGRect(x: 10, y: 20, width: 100, height: 50))
    }

    func testAspectRatioDerivesHeightFromWidthAndKeepsDirection() {
        let down = CropAreaNSView.creationRect(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 5), aspectRatio: 2)
        XCTAssertEqual(down, CGRect(x: 0, y: 0, width: 200, height: 100))

        let up = CropAreaNSView.creationRect(from: CGPoint(x: 0, y: 300), to: CGPoint(x: 200, y: 295), aspectRatio: 2)
        XCTAssertEqual(up, CGRect(x: 0, y: 200, width: 200, height: 100))
    }
}
