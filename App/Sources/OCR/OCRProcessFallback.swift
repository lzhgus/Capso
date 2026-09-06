import CoreGraphics
import Darwin
import Foundation
import ImageIO
import OCRKit
import UniformTypeIdentifiers

/// Retries Vision OCR in a clean Capso process when the OS's in-process
/// TextRecognition service has entered its broken Neural Engine state.
///
/// Some macOS preview builds return `TextRecognition.CRImageReaderError` for
/// every recognition after the first one in a process. A new process uses the
/// model's initial-load path and succeeds, so this is deliberately a fallback
/// rather than Capso's normal OCR path.
enum OCRProcessFallback {
    private static let helperArgument = "--capso-ocr-helper"

    static var shouldSkipPrewarm: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27
    }

    static func recognize(
        image: CGImage,
        languages: [String]? = nil,
        level: RecognitionLevel = .accurate,
        detectURLs: Bool = true
    ) async throws -> [TextRegion] {
        do {
            return try await TextRecognizer.recognize(
                image: image,
                languages: languages,
                level: level,
                detectURLs: detectURLs
            )
        } catch {
            guard shouldRetryInFreshProcess(error) else { throw error }
            return try await Task.detached(priority: .userInitiated) {
                try recognizeInFreshProcess(
                    image: image,
                    languages: languages,
                    level: level,
                    detectURLs: detectURLs
                )
            }.value
        }
    }

    /// Runs before normal Capso startup when this executable was launched by
    /// `recognizeInFreshProcess`. It intentionally performs only one direct
    /// Vision request, then exits without creating windows or registering
    /// shortcuts.
    static func runHelperIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard arguments.count == 6, arguments[1] == helperArgument,
              let inputURL = URL(string: arguments[2]),
              let outputURL = URL(string: arguments[3]),
              let level = recognitionLevel(for: arguments[4]) else {
            return false
        }

        let detectURLs = arguments[5] == "1"
        let semaphore = DispatchSemaphore(value: 0)
        let exitCode = ExitCodeBox()

        Task.detached(priority: .userInitiated) {
            defer { semaphore.signal() }
            do {
                let regions = try await recognizeImageFile(
                    at: inputURL,
                    languages: nil,
                    level: level,
                    detectURLs: detectURLs
                )
                let data = try JSONEncoder().encode(regions.map(EncodedRegion.init))
                try data.write(to: outputURL, options: .atomic)
                exitCode.value = 0
            } catch {
                fputs("Capso OCR helper failed: \(error.localizedDescription)\n", stderr)
            }
        }
        semaphore.wait()
        exit(exitCode.value)
    }

    private static func shouldRetryInFreshProcess(_ error: Error) -> Bool {
        let description = error.localizedDescription
        return description.contains("TextRecognition.CRImageReaderError")
            || String(describing: error).contains("CRImageReaderError")
    }

    private static func recognizeInFreshProcess(
        image: CGImage,
        languages: [String]?,
        level: RecognitionLevel,
        detectURLs: Bool
    ) throws -> [TextRegion] {
        // The helper intentionally mirrors automatic language detection. The
        // current app callers do not supply an explicit language list; fail
        // closed rather than silently producing a different recognition mode.
        guard languages == nil else { throw OCRProcessFallbackError.explicitLanguagesUnsupported }
        guard let executableURL = Bundle.main.executableURL else {
            throw OCRProcessFallbackError.executableNotFound
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapsoOCR-\(UUID().uuidString)", isDirectory: true)
        let inputURL = directory.appendingPathComponent("input.png")
        let outputURL = directory.appendingPathComponent("regions.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writePNG(image, to: inputURL)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            helperArgument,
            inputURL.absoluteString,
            outputURL.absoluteString,
            level == .fast ? "fast" : "accurate",
            detectURLs ? "1" : "0"
        ]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw OCRProcessFallbackError.helperFailed(process.terminationStatus)
        }
        let data = try Data(contentsOf: outputURL)
        let regions = try JSONDecoder().decode([EncodedRegion].self, from: data)
        return regions.map(TextRegion.init)
    }

    private static func recognizeImageFile(
        at url: URL,
        languages: [String]?,
        level: RecognitionLevel,
        detectURLs: Bool
    ) async throws -> [TextRegion] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OCRProcessFallbackError.invalidInputImage
        }
        return try await TextRecognizer.recognize(
            image: image,
            languages: languages,
            level: level,
            detectURLs: detectURLs
        )
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw OCRProcessFallbackError.cannotEncodeImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw OCRProcessFallbackError.cannotEncodeImage
        }
    }

    private static func recognitionLevel(for value: String) -> RecognitionLevel? {
        switch value {
        case "fast": .fast
        case "accurate": .accurate
        default: nil
        }
    }
}

private struct EncodedRegion: Codable {
    let text: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let confidence: Float
    let isURL: Bool

    init(_ region: TextRegion) {
        text = region.text
        x = region.boundingBox.origin.x
        y = region.boundingBox.origin.y
        width = region.boundingBox.width
        height = region.boundingBox.height
        confidence = region.confidence
        isURL = region.isURL
    }

    func makeTextRegion() -> TextRegion {
        TextRegion(
            text: text,
            boundingBox: CGRect(x: x, y: y, width: width, height: height),
            confidence: confidence,
            isURL: isURL
        )
    }
}

private extension TextRegion {
    init(_ encoded: EncodedRegion) {
        self = encoded.makeTextRegion()
    }
}

private enum OCRProcessFallbackError: LocalizedError {
    case executableNotFound
    case explicitLanguagesUnsupported
    case invalidInputImage
    case cannotEncodeImage
    case helperFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .executableNotFound: "Could not find Capso's executable."
        case .explicitLanguagesUnsupported: "OCR fallback does not support explicit languages."
        case .invalidInputImage: "Could not read the temporary OCR image."
        case .cannotEncodeImage: "Could not prepare the image for OCR retry."
        case .helperFailed(let status): "OCR retry process exited with status \(status)."
        }
    }
}

private final class ExitCodeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Int32 = 1

    var value: Int32 {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedValue = newValue
        }
    }
}
