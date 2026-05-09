// Packages/OCRKit/Sources/OCRKit/TextRecognizer.swift
import Foundation
import CoreGraphics
import Vision

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
    public static func recognize(
        image: CGImage,
        languages: [String]? = nil,
        level: RecognitionLevel = .accurate,
        detectURLs: Bool = true
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
