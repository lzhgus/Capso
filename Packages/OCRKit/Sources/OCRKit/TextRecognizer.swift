// Packages/OCRKit/Sources/OCRKit/TextRecognizer.swift
import Foundation
import CoreGraphics
import os
import Vision

private let logger = Logger(subsystem: "com.awesomemacapps.capso", category: "OCRKit")

/// Recognition accuracy level.
public enum RecognitionLevel: Sendable {
    case fast
    case accurate
}

/// Core OCR engine using Apple Vision framework.
public enum TextRecognizer {

    /// Recognize text regions in a CGImage.
    /// Returns regions sorted top-to-bottom, left-to-right.
    /// Bounding boxes are in image coordinates (top-left origin, pixel dimensions).
    ///
    /// The `.accurate` level runs Vision's neural network on the Apple Neural
    /// Engine. When that system runtime is degraded — a macOS-wide condition
    /// that shows up as `E5RT … Code: 13` in the unified log — every accurate
    /// request fails with `TextRecognition.CRImageReaderError error 1`, while
    /// the `.fast` level (no neural network) keeps working. Rather than fail
    /// the whole capture, fall back to `.fast` for that call — but only when
    /// `.fast` supports the user's languages, since it turns CJK into garbage.
    public static func recognize(
        image: CGImage,
        languages: [String]? = nil,
        level: RecognitionLevel = .accurate,
        detectURLs: Bool = true
    ) async throws -> [TextRegion] {
        try await recognize(
            image: image,
            languages: languages,
            level: level,
            detectURLs: detectURLs,
            allowsFastFallback: { fastSupports(Locale.preferredLanguages, fastLanguages: fastLanguages()) },
            run: recognizeWithVision
        )
    }

    /// Recognition with an injectable runner, so the neural-engine fallback
    /// below can be exercised without a real (and non-reproducible) ANE fault.
    static func recognize(
        image: CGImage,
        languages: [String]?,
        level: RecognitionLevel,
        detectURLs: Bool,
        allowsFastFallback: () -> Bool = { true },
        run: @Sendable (CGImage, [String]?, RecognitionLevel, Bool) async throws -> [TextRegion]
    ) async throws -> [TextRegion] {
        do {
            return try await run(image, languages, level, detectURLs)
        } catch let accurateError {
            // Only `.accurate` has a fallback; an explicit `.fast` failure is
            // the underlying error and must propagate unchanged.
            guard level == .accurate, allowsFastFallback() else { throw accurateError }

            logger.warning("""
                Accurate OCR failed, retrying with the fast level: \
                \(accurateError.localizedDescription, privacy: .public)
                """)
            do {
                return try await run(image, languages, .fast, detectURLs)
            } catch {
                throw accurateError
            }
        }
    }

    /// True when every preferred language is one the `.fast` level can read.
    static func fastSupports(_ preferredLanguages: [String], fastLanguages: [String]) -> Bool {
        let supported = Set(fastLanguages.compactMap { Locale.Language(identifier: $0).languageCode })
        return preferredLanguages.allSatisfy { identifier in
            Locale.Language(identifier: identifier).languageCode.map(supported.contains) ?? false
        }
    }

    private static func fastLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        return (try? request.supportedRecognitionLanguages()) ?? []
    }

    private static func recognizeWithVision(
        image: CGImage,
        languages: [String]?,
        level: RecognitionLevel,
        detectURLs: Bool
    ) async throws -> [TextRegion] {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)

        return try await withCheckedThrowingContinuation { continuation in
            let oneShot = OneShotContinuation(continuation)
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    oneShot.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    oneShot.resume(returning: [])
                    return
                }

                let urlPattern = try? NSRegularExpression(
                    pattern: #"https?://[^\s]+"#,
                    options: .caseInsensitive
                )

                var regions: [TextRegion] = []
                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }

                    // Convert Vision's bottom-left normalized coords to top-left image coords
                    let vnBox = observation.boundingBox
                    let pixelRect = CGRect(
                        x: vnBox.origin.x * imageWidth,
                        y: (1 - vnBox.origin.y - vnBox.height) * imageHeight,
                        width: vnBox.width * imageWidth,
                        height: vnBox.height * imageHeight
                    )

                    let text = candidate.string
                    var isURL = false
                    if detectURLs, let urlPattern {
                        let range = NSRange(text.startIndex..., in: text)
                        isURL = urlPattern.firstMatch(in: text, range: range) != nil
                    }

                    regions.append(TextRegion(
                        text: text,
                        boundingBox: pixelRect,
                        confidence: candidate.confidence,
                        isURL: isURL
                    ))
                }

                // Sort top-to-bottom, then left-to-right
                regions.sort { a, b in
                    if abs(a.boundingBox.minY - b.boundingBox.minY) < 10 {
                        return a.boundingBox.minX < b.boundingBox.minX
                    }
                    return a.boundingBox.minY < b.boundingBox.minY
                }

                oneShot.resume(returning: regions)
            }

            request.recognitionLevel = level == .fast
                ? .fast : .accurate
            if let languages {
                request.recognitionLanguages = languages
            }
            request.automaticallyDetectsLanguage = languages == nil
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                oneShot.resume(throwing: error)
            }
        }
    }

    /// Prewarm Vision's text-recognition models so the first real OCR request
    /// doesn't pay the one-time model-loading cost. Runs a throwaway request
    /// (with the same configuration as a real call) on a blank image.
    /// Safe to call from a background task at app launch; errors are ignored.
    public static func prewarm() async {
        guard let image = makeBlankImage() else { return }
        _ = try? await recognize(image: image, level: .accurate, detectURLs: false)
    }

    private static func makeBlankImage() -> CGImage? {
        let size = 64
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()
    }

    /// Convenience: recognize and return joined text string.
    public static func recognizeText(
        image: CGImage,
        keepLineBreaks: Bool = true,
        languages: [String]? = nil
    ) async throws -> String {
        let regions = try await recognize(
            image: image,
            languages: languages,
            level: .accurate,
            detectURLs: false
        )
        let separator = keepLineBreaks ? "\n" : " "
        return regions.map(\.text).joined(separator: separator)
    }
}

final class OneShotContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(returning value: Value) -> Bool {
        guard let continuation = takeContinuation() else { return false }
        continuation.resume(returning: value)
        return true
    }

    @discardableResult
    func resume(throwing error: Error) -> Bool {
        guard let continuation = takeContinuation() else { return false }
        continuation.resume(throwing: error)
        return true
    }

    private func takeContinuation() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }

        let continuation = continuation
        self.continuation = nil
        return continuation
    }
}
