import CoreGraphics
import XCTest
@testable import Capso

@MainActor
final class CropAreaCreationRectTests: XCTestCase {
    private let bounds = CGSize(width: 1000, height: 800)

    func testDragDownRightProducesRectFromStart() {
        let rect = CropAreaNSView.creationRect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 110, y: 70), aspectRatio: nil, in: bounds)
        XCTAssertEqual(rect, CGRect(x: 10, y: 20, width: 100, height: 50))
    }

    func testDragUpLeftIsNormalised() {
        let rect = CropAreaNSView.creationRect(from: CGPoint(x: 110, y: 70), to: CGPoint(x: 10, y: 20), aspectRatio: nil, in: bounds)
        XCTAssertEqual(rect, CGRect(x: 10, y: 20, width: 100, height: 50))
    }

    func testAspectRatioDerivesHeightFromWidthAndKeepsDirection() {
        let down = CropAreaNSView.creationRect(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 5), aspectRatio: 2, in: bounds)
        XCTAssertEqual(down, CGRect(x: 0, y: 0, width: 200, height: 100))

        let up = CropAreaNSView.creationRect(from: CGPoint(x: 0, y: 300), to: CGPoint(x: 200, y: 295), aspectRatio: 2, in: bounds)
        XCTAssertEqual(up, CGRect(x: 0, y: 200, width: 200, height: 100))
    }

    func testAspectRatioSurvivesTheImageEdge() {
        let rect = CropAreaNSView.creationRect(from: CGPoint(x: 100, y: 700), to: CGPoint(x: 400, y: 750), aspectRatio: 1, in: bounds)
        XCTAssertEqual(rect, CGRect(x: 100, y: 700, width: 100, height: 100))
    }

    func testDragPastTheEdgeStopsAtTheImage() {
        let rect = CropAreaNSView.creationRect(from: CGPoint(x: 900, y: 700), to: CGPoint(x: 1200, y: 900), aspectRatio: nil, in: bounds)
        XCTAssertEqual(rect, CGRect(x: 900, y: 700, width: 100, height: 100))
    }
}
