import XCTest
@testable import OCRKit

final class OCRKitTests: XCTestCase {
    func testOneShotContinuationIgnoresSecondResume() async throws {
        let value: String = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let oneShot = OneShotContinuation(continuation)

            XCTAssertTrue(oneShot.resume(returning: "first"))
            XCTAssertFalse(oneShot.resume(returning: "second"))
        }

        XCTAssertEqual(value, "first")
    }

    /// Prewarm must complete without throwing or crashing, even though it
    /// recognizes a blank image with no text in it.
    func testPrewarmCompletes() async {
        await TextRecognizer.prewarm()
    }

    // MARK: - Neural engine fallback

    private static let accurateEngineError = NSError(
        domain: "TextRecognition.CRImageReaderError",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed. (TextRecognition.CRImageReaderError error 1.)"]
    )

    private func blankImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    /// A degraded system Neural Engine fails every `.accurate` request. The
    /// capture must still produce text by degrading to the `.fast` level
    /// instead of surfacing the error to the user.
    func testAccurateFailureFallsBackToFast() async throws {
        let image = try blankImage()
        let fastRegion = TextRegion(text: "fast", boundingBox: .zero, confidence: 1)
        let levels = Locked<[RecognitionLevel]>([])

        let regions = try await TextRecognizer.recognize(
            image: image,
            languages: nil,
            level: .accurate,
            detectURLs: false
        ) { _, _, level, _ in
            levels.withLock { $0.append(level) }
            switch level {
            case .accurate:
                throw Self.accurateEngineError
            case .fast:
                return [fastRegion]
            }
        }

        XCTAssertEqual(levels.value, [.accurate, .fast])
        XCTAssertEqual(regions.map(\.text), ["fast"])
    }

    /// `.fast` can't read CJK, so falling back would hand the user garbage.
    /// Without fallback support the original accurate error must surface.
    func testNoFallbackWhenFastCannotReadUserLanguages() async throws {
        let image = try blankImage()
        let levels = Locked<[RecognitionLevel]>([])

        do {
            _ = try await TextRecognizer.recognize(
                image: image,
                languages: nil,
                level: .accurate,
                detectURLs: false,
                allowsFastFallback: { false }
            ) { _, _, level, _ in
                levels.withLock { $0.append(level) }
                throw Self.accurateEngineError
            }
            XCTFail("Expected the accurate failure to propagate")
        } catch {
            XCTAssertEqual((error as NSError).domain, "TextRecognition.CRImageReaderError")
        }

        XCTAssertEqual(levels.value, [.accurate])
    }

    func testFastSupportsOnlyLatinScriptLanguages() {
        let fast = ["en-US", "fr-FR", "it-IT", "de-DE", "es-ES", "pt-BR"]
        XCTAssertTrue(TextRecognizer.fastSupports(["en-GB", "de-CH"], fastLanguages: fast))
        XCTAssertFalse(TextRecognizer.fastSupports(["zh-Hans-CN"], fastLanguages: fast))
        XCTAssertFalse(TextRecognizer.fastSupports(["en-US", "ja-JP"], fastLanguages: fast))
        XCTAssertFalse(TextRecognizer.fastSupports(["ko-KR"], fastLanguages: []))
    }

    /// A successful `.accurate` request must not pay for a second pass.
    func testAccurateSuccessDoesNotFallBack() async throws {
        let image = try blankImage()
        let accurateRegion = TextRegion(text: "accurate", boundingBox: .zero, confidence: 1)
        let levels = Locked<[RecognitionLevel]>([])

        let regions = try await TextRecognizer.recognize(
            image: image,
            languages: nil,
            level: .accurate,
            detectURLs: false
        ) { _, _, level, _ in
            levels.withLock { $0.append(level) }
            return [accurateRegion]
        }

        XCTAssertEqual(levels.value, [.accurate])
        XCTAssertEqual(regions.map(\.text), ["accurate"])
    }

    /// `.fast` is already the fallback, so its failure is the real error and
    /// must propagate rather than being retried or masked.
    func testFastFailurePropagatesWithoutRetry() async throws {
        let image = try blankImage()
        let levels = Locked<[RecognitionLevel]>([])

        do {
            _ = try await TextRecognizer.recognize(
                image: image,
                languages: nil,
                level: .fast,
                detectURLs: false
            ) { _, _, level, _ in
                levels.withLock { $0.append(level) }
                throw Self.accurateEngineError
            }
            XCTFail("Expected the fast-level failure to propagate")
        } catch {
            XCTAssertEqual((error as NSError).domain, "TextRecognition.CRImageReaderError")
        }

        XCTAssertEqual(levels.value, [.fast])
    }

    /// When the fallback fails too, the reported error must stay the original
    /// `.accurate` failure so the user still sees the real cause.
    func testFallbackFailureReportsOriginalError() async throws {
        let image = try blankImage()
        let levels = Locked<[RecognitionLevel]>([])

        do {
            _ = try await TextRecognizer.recognize(
                image: image,
                languages: nil,
                level: .accurate,
                detectURLs: false
            ) { _, _, level, _ in
                levels.withLock { $0.append(level) }
                if level == .fast {
                    throw NSError(domain: "TextRecognition.FastFailure", code: 7)
                }
                throw Self.accurateEngineError
            }
            XCTFail("Expected recognition to fail")
        } catch {
            XCTAssertEqual((error as NSError).domain, "TextRecognition.CRImageReaderError")
        }

        XCTAssertEqual(levels.value, [.accurate, .fast])
    }
}

/// Minimal lock box so the injected runners can record call arguments from
/// Vision's background callback without tripping strict concurrency.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        self.storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withLock(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storage)
    }
}
