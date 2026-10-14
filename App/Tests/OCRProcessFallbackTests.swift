import CoreGraphics
import OCRKit
import XCTest
@testable import Capso

final class OCRProcessFallbackTests: XCTestCase {
    private static let engineError = NSError(
        domain: "TextRecognition.CRImageReaderError", code: 1
    )

    func testSuccessfulRecognitionDoesNotLaunchHelper() async throws {
        let regions = try await OCRProcessFallback.recognize(
            image: makeImage(), languages: nil, level: .accurate, detectURLs: false,
            run: { _, _, _, _ in
                [TextRegion(text: "recognized", boundingBox: .zero, confidence: 1)]
            },
            retry: { _, _, _, _ in
                XCTFail("Successful OCR must not launch a helper")
                return []
            }
        )
        XCTAssertEqual(regions.map(\.text), ["recognized"])
    }

    func testEngineFailureRetriesWithTheRequestedOptionsAndPreservesRegions() async throws {
        let regions = try await OCRProcessFallback.recognize(
            image: makeImage(), languages: nil, level: .accurate, detectURLs: true,
            run: { _, _, _, _ in throw Self.engineError },
            retry: { image, languages, level, detectURLs in
                XCTAssertEqual(image.width, 8)
                XCTAssertNil(languages)
                XCTAssertEqual(level, .accurate)
                XCTAssertTrue(detectURLs)
                return [TextRegion(
                    text: "https://example.com", boundingBox: CGRect(x: 1, y: 2, width: 3, height: 4),
                    confidence: 0.9, isURL: true
                )]
            }
        )
        let region = try XCTUnwrap(regions.first)
        XCTAssertEqual(region.text, "https://example.com")
        XCTAssertEqual(region.boundingBox, CGRect(x: 1, y: 2, width: 3, height: 4))
        XCTAssertEqual(region.confidence, 0.9)
        XCTAssertTrue(region.isURL)
    }

    func testUnrelatedErrorDoesNotLaunchHelper() async throws {
        do {
            _ = try await OCRProcessFallback.recognize(
                image: makeImage(), languages: nil, level: .fast, detectURLs: false,
                run: { _, _, _, _ in throw NSError(domain: "OtherOCRFailure", code: 42) },
                retry: { _, _, _, _ in
                    XCTFail("Unrelated failures must not launch a helper")
                    return []
                }
            )
            XCTFail("Expected the original error")
        } catch {
            XCTAssertEqual((error as NSError).domain, "OtherOCRFailure")
            XCTAssertEqual((error as NSError).code, 42)
        }
    }

    func testHelperFailurePropagatesWithoutAnotherRetry() async throws {
        do {
            _ = try await OCRProcessFallback.recognize(
                image: makeImage(), languages: nil, level: .accurate, detectURLs: false,
                run: { _, _, _, _ in throw Self.engineError },
                retry: { _, _, _, _ in throw NSError(domain: "HelperFailure", code: 2) }
            )
            XCTFail("Expected helper failure")
        } catch {
            XCTAssertEqual((error as NSError).domain, "HelperFailure")
            XCTAssertEqual((error as NSError).code, 2)
        }
    }

    func testFreshHelperProcessReturnsRegionsForBlankImage() async throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 640, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 160))
        let regions = try await OCRProcessFallback.recognize(
            image: XCTUnwrap(context.makeImage()), languages: nil, level: .accurate, detectURLs: false,
            run: { _, _, _, _ in throw Self.engineError }
        )
        XCTAssertTrue(regions.isEmpty)
    }

    private func makeImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }
}
