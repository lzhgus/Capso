import AVFoundation
import EditorKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Capso

final class EditorGIFExportTests: XCTestCase {
    func testCompositedGIFExportProducesGIFData() async throws {
        let sourceURL = try EditorVideoFixture.make()
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-editor-\(UUID().uuidString)")
            .appendingPathExtension("gif")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destinationURL)
        }

        var backgroundStyle = BackgroundStyle.default
        backgroundStyle.enabled = true
        let project = RecordingProject(
            sourceVideoURL: sourceURL,
            showsCursor: false,
            videoDuration: 0.4,
            videoSize: CGSize(width: 160, height: 120),
            recordingAreaSize: CGSize(width: 160, height: 120),
            backgroundStyle: backgroundStyle
        )
        let coordinator = await MainActor.run {
            EditorCoordinator(project: project, outputFormat: .gif)
        }
        let exportFormat = await MainActor.run {
            coordinator.outputFormat.exportFormat
        }

        let exportedURL = try await coordinator.exportVideo(
            format: exportFormat,
            quality: .maximum,
            destination: destinationURL
        )

        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(exportedURL as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(imageSource) as String?, UTType.gif.identifier)
        XCTAssertGreaterThan(CGImageSourceGetCount(imageSource), 1)
    }
}

private enum EditorVideoFixture {
    enum FixtureError: Error {
        case writerSetupFailed
        case pixelBufferCreationFailed
        case writerFinishFailed(Error?)
    }

    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-editor-source-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let width = 160
        let height = 120
        let fps: Int32 = 15
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        guard writer.canAdd(input) else { throw FixtureError.writerSetupFailed }
        writer.add(input)
        guard writer.startWriting() else { throw FixtureError.writerSetupFailed }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<6 {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard let pixelBuffer = makePixelBuffer(width: width, height: height) else {
                throw FixtureError.pixelBufferCreationFailed
            }
            let presentationTime = CMTime(value: Int64(frame), timescale: fps)
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw FixtureError.writerFinishFailed(writer.error)
            }
        }
        input.markAsFinished()

        let finished = DispatchGroup()
        finished.enter()
        writer.finishWriting { finished.leave() }
        finished.wait()
        guard writer.status == .completed else {
            throw FixtureError.writerFinishFailed(writer.error)
        }
        return url
    }

    private static func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let address = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(address, 0x44, CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }
}
