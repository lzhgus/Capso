// Packages/SharedKit/Tests/SharedKitTests/FileNamingTests.swift
import Testing
import Foundation
@testable import SharedKit

@Suite("FileNaming")
struct FileNamingTests {
    @Test("Default screenshot name contains 'Capso Screenshot'")
    func defaultScreenshotName() {
        let name = FileNaming.generateName(for: .screenshot)
        #expect(name.hasPrefix("Capso Screenshot"))
    }

    @Test("Default recording name contains 'Capso Recording'")
    func defaultRecordingName() {
        let name = FileNaming.generateName(for: .recording)
        #expect(name.hasPrefix("Capso Recording"))
    }

    @Test("Name includes date components")
    func nameIncludesDate() {
        let name = FileNaming.generateName(for: .screenshot)
        let year = Calendar.current.component(.year, from: Date())
        #expect(name.contains(String(year)))
    }

    @Test("Screenshot name includes source app when provided")
    func screenshotNameIncludesSourceApp() {
        let date = Date(timeIntervalSince1970: 1_705_348_800)
        let name = FileNaming.generateName(for: .screenshot, date: date, sourceAppName: "Safari")

        #expect(name.hasPrefix("Capso Screenshot - Safari "))
    }

    @Test("Source app name is sanitized for filenames")
    func sourceAppNameIsSanitized() {
        let date = Date(timeIntervalSince1970: 1_705_348_800)
        let fileName = FileNaming.generateFileName(
            for: .screenshot,
            format: .png,
            date: date,
            sourceAppName: "Foo/Bar:Beta"
        )

        #expect(fileName.hasPrefix("Capso Screenshot - Foo-Bar-Beta "))
        #expect(fileName.hasSuffix(".png"))
    }

    @Test("File extension for PNG")
    func fileExtensionPNG() {
        let ext = FileNaming.fileExtension(for: .png)
        #expect(ext == "png")
    }

    @Test("File extension for MP4")
    func fileExtensionMP4() {
        let ext = FileNaming.fileExtension(for: .mp4)
        #expect(ext == "mp4")
    }

    @Test("File extension for GIF")
    func fileExtensionGIF() {
        let ext = FileNaming.fileExtension(for: .gif)
        #expect(ext == "gif")
    }

    @Test("Monthly directory uses year and month")
    func monthlyDirectoryUsesYearAndMonth() {
        let base = URL(fileURLWithPath: "/tmp/capso-test", isDirectory: true)
        let date = Date(timeIntervalSince1970: 1_705_348_800)

        let directory = FileNaming.monthlyDirectory(in: base, date: date)

        #expect(directory.lastPathComponent == "2024-01")
        #expect(directory.deletingLastPathComponent() == base)
    }
}
