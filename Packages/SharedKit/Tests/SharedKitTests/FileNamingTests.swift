// Packages/SharedKit/Tests/SharedKitTests/FileNamingTests.swift
import Testing
import Foundation
@testable import SharedKit

@Suite("FileNaming")
struct FileNamingTests {
    private func localDate(
        year: Int = 2024,
        month: Int = 1,
        day: Int = 15,
        hour: Int = 16,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date!
    }

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

    @Test("Custom screenshot template can omit Capso prefix")
    func customScreenshotTemplateOmitsCapsoPrefix() {
        let date = localDate()
        let fileName = FileNaming.generateFileName(
            for: .screenshot,
            format: .png,
            date: date,
            template: "{date}-{time}"
        )

        #expect(fileName == "2024-01-15-16.00.00.png")
    }

    @Test("Screenshot template renders source app and window tokens")
    func screenshotTemplateRendersSourceTokens() {
        let date = localDate()
        let fileName = FileNaming.generateFileName(
            for: .screenshot,
            format: .png,
            date: date,
            sourceAppName: "Foo/Bar:Beta",
            sourceWindowTitle: "Doc/One:Draft",
            template: "{app}-{window}-{timestamp}"
        )

        #expect(fileName == "Foo-Bar-Beta-Doc-One-Draft-2024-01-15 at 16.00.00.png")
    }

    @Test("Screenshot source token includes separator only when app exists")
    func screenshotSourceTokenIncludesSeparatorOnlyWhenAppExists() {
        let date = localDate()

        let withApp = FileNaming.generateName(
            for: .screenshot,
            date: date,
            sourceAppName: "Safari",
            template: "Capso Screenshot{source} {timestamp}"
        )
        let withoutApp = FileNaming.generateName(
            for: .screenshot,
            date: date,
            template: "Capso Screenshot{source} {timestamp}"
        )

        #expect(withApp == "Capso Screenshot - Safari 2024-01-15 at 16.00.00")
        #expect(withoutApp == "Capso Screenshot 2024-01-15 at 16.00.00")
    }

    @Test("Unknown filename tokens remain visible")
    func unknownFilenameTokensRemainVisible() {
        let date = localDate()
        let name = FileNaming.generateName(
            for: .screenshot,
            date: date,
            template: "Shot {date} {project}"
        )

        #expect(name == "Shot 2024-01-15 {project}")
    }

    @Test("Empty filename template falls back to screenshot default")
    func emptyFilenameTemplateFallsBackToScreenshotDefault() {
        let date = localDate()
        let name = FileNaming.generateName(
            for: .screenshot,
            date: date,
            template: "   "
        )

        #expect(name == "Capso Screenshot 2024-01-15 at 16.00.00")
    }

    @Test("Rendered filename strips unsafe characters")
    func renderedFilenameStripsUnsafeCharacters() {
        let date = localDate()
        let fileName = FileNaming.generateFileName(
            for: .screenshot,
            format: .png,
            date: date,
            sourceWindowTitle: "Doc\u{0001}/One:Draft.",
            template: " {window}. "
        )

        #expect(fileName == "Doc-One-Draft.png")
    }

    @Test("Random filename token is lowercase base36")
    func randomFilenameTokenIsLowercaseBase36() {
        let name = FileNaming.generateName(
            for: .screenshot,
            template: "{random}"
        )

        #expect(name.count == 8)
        #expect(name.range(of: #"^[0-9a-z]{8}$"#, options: String.CompareOptions.regularExpression) != nil)
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
