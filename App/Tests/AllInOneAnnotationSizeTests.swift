import CoreGraphics
import XCTest
@testable import Capso

@MainActor
final class AllInOneAnnotationSizeTests: XCTestCase {
    private let keys = ["annotationShapeWidth", "annotationTextFontSize", "annotationLastTool"]
    private var saved: [String: Any] = [:]

    override func setUp() async throws {
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
        UserDefaults.standard.set(3.0, forKey: "annotationShapeWidth")
        UserDefaults.standard.set(48.0, forKey: "annotationTextFontSize")
        UserDefaults.standard.set("arrow", forKey: "annotationLastTool")
    }

    override func tearDown() async throws {
        for key in keys { UserDefaults.standard.set(saved[key], forKey: key) }
    }

    private func makeSession() -> AllInOneAnnotationSession {
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return AllInOneAnnotationSession(sourceImage: ctx.makeImage()!, displayScale: 1)
    }

    private var storedShapeWidth: Double { UserDefaults.standard.double(forKey: "annotationShapeWidth") }
    private var storedFontSize: Double { UserDefaults.standard.double(forKey: "annotationTextFontSize") }

    func testSwitchingToolsKeepsBothSizes() {
        let session = makeSession()
        session.switchTool(.text)
        session.switchTool(.arrow)
        XCTAssertEqual(session.lineWidth, 3)
        XCTAssertEqual(session.textFontSize, 48)
    }

    func testSwitchingToArrowWhileEditingTextKeepsTheFontSize() {
        let session = makeSession()
        session.switchTool(.text)
        session.isEditingText = true
        session.switchTool(.arrow)
        XCTAssertEqual(session.textFontSize, 48)
        session.isEditingText = false
        XCTAssertEqual(storedFontSize, 48)
        XCTAssertEqual(storedShapeWidth, 3)
    }

    func testReeditingTextUnderSelectDoesNotChangeArrowWidth() {
        let session = makeSession()
        session.switchTool(.select)
        session.isEditingText = true
        session.textFontSize = 64
        session.isEditingText = false
        session.switchTool(.arrow)
        XCTAssertEqual(session.lineWidth, 3)
        XCTAssertEqual(storedShapeWidth, 3)
    }

    func testFontSliderUnderSelectSavesTheFontSize() {
        let session = makeSession()
        session.switchTool(.select)
        session.isEditingText = true
        session.setSliderValue(64)
        XCTAssertEqual(storedFontSize, 64)
        XCTAssertEqual(storedShapeWidth, 3)
    }
}
