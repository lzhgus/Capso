import CoreGraphics
import Foundation
import ImageIO
import OCRKit
import UniformTypeIdentifiers
import XCTest
@testable import Capso

final class OCRPrewarmIntegrationTests: XCTestCase {
    func testExecutableHelperRecognizesPrewarmSample() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapsoOCRPrewarmTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("sample.png")
        let output = directory.appendingPathComponent("regions.json")
        await TextRecognizer.prewarm { image in
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
                input as CFURL, UTType.png.identifier as CFString, 1, nil
            ))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return []
        }
        let executable = try XCTUnwrap(Bundle.main.executableURL)
        let status = try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--capso-ocr-helper", input.absoluteString, output.absoluteString, "accurate", "0"]
            try process.run()
            defer { if process.isRunning { process.terminate() } }
            let deadline = Date().addingTimeInterval(90)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            return process.terminationStatus
        }.value
        XCTAssertEqual(status, 0)
        struct Region: Decodable { let text: String }
        let regions = try JSONDecoder().decode([Region].self, from: Data(contentsOf: output))
        let text = regions.map(\.text).joined(separator: " ")
        XCTAssertTrue(text.contains("Capso"), text)
        XCTAssertTrue(text.contains("中文"), text)
    }
}
