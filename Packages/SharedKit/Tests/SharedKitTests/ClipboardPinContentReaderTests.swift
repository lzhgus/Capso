import AppKit
import Testing
@testable import SharedKit

@Suite("ClipboardPinContentReader")
struct ClipboardPinContentReaderTests {
    @Test("keeps clipboard images at their original pixel dimensions")
    @MainActor
    func keepsClipboardImages() throws {
        let pasteboard = makePasteboard()
        let source = try makeImage(width: 11, height: 7)
        pasteboard.writeObjects([ImageUtilities.nsImage(from: source)])

        let result = ClipboardPinContentReader.render(from: pasteboard)

        guard case let .image(image) = result else {
            Issue.record("Expected the clipboard image, got \(result)")
            return
        }
        #expect(image.width == 11)
        #expect(image.height == 7)
    }

    @Test("rejects image dimensions that exceed the clipboard pin memory budget")
    @MainActor
    func validatesImageDimensions() {
        #expect(ClipboardPinContentReader.isSafeImageDimensions(width: 6_016, height: 3_384))
        #expect(!ClipboardPinContentReader.isSafeImageDimensions(width: 50_000, height: 50_000))
        #expect(!ClipboardPinContentReader.isSafeImageDimensions(width: .max, height: 2))
        #expect(!ClipboardPinContentReader.isSafeImageDimensions(width: 0, height: 100))
    }

    @Test("renders hexadecimal clipboard colors as color cards")
    @MainActor
    func rendersHexColorCard() throws {
        let pasteboard = makePasteboard()
        pasteboard.setString("#00FF80", forType: .string)

        let result = ClipboardPinContentReader.render(from: pasteboard)

        guard case let .image(image) = result else {
            Issue.record("Expected a color card, got \(result)")
            return
        }
        #expect(image.colorSpace?.name == CGColorSpace.sRGB)
        #expect(image.bitsPerComponent == 8)
        #expect(try rgbaPixel(in: image, x: 10, y: 10) == [0, 255, 128, 255])
    }

    @Test("renders integer RGB clipboard colors as color cards")
    @MainActor
    func rendersIntegerRGBColorCard() throws {
        let pasteboard = makePasteboard()
        pasteboard.setString("rgb(255, 0, 128)", forType: .string)

        let result = ClipboardPinContentReader.render(from: pasteboard)

        guard case let .image(image) = result else {
            Issue.record("Expected a color card, got \(result)")
            return
        }
        #expect(try rgbaPixel(in: image, x: 10, y: 10) == [255, 0, 128, 255])
    }

    @Test("renders normalized RGB clipboard colors as color cards")
    @MainActor
    func rendersNormalizedRGBColorCard() throws {
        let pasteboard = makePasteboard()
        pasteboard.setString("1, 0.5, 0", forType: .string)

        let result = ClipboardPinContentReader.render(from: pasteboard)

        guard case let .image(image) = result else {
            Issue.record("Expected a color card, got \(result)")
            return
        }
        #expect(try rgbaPixel(in: image, x: 10, y: 10) == [255, 128, 0, 255])
    }

    @Test("preserves RTF font and color attributes")
    @MainActor
    func preservesRTFAttributes() throws {
        let pasteboard = makePasteboard()
        let source = NSAttributedString(
            string: "Styled text",
            attributes: [
                .font: NSFont.systemFont(ofSize: 26, weight: .bold),
                .foregroundColor: NSColor.systemRed,
            ]
        )
        let data = try source.data(
            from: NSRange(location: 0, length: source.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        pasteboard.setData(data, forType: .rtf)

        let parsed = try #require(ClipboardPinContentReader.attributedText(from: pasteboard))
        let font = try #require(parsed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let color = try #require(parsed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)

        #expect(font.pointSize == 26)
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(color.usingColorSpace(.sRGB) == NSColor.systemRed.usingColorSpace(.sRGB))
    }

    @Test("renders RTF clipboard content as a pin image")
    @MainActor
    func rendersRTF() throws {
        let pasteboard = makePasteboard()
        let source = NSAttributedString(
            string: Array(repeating: "Styled text", count: 10).joined(separator: "\n"),
            attributes: [.font: NSFont.systemFont(ofSize: 42, weight: .bold)]
        )
        let data = try source.data(
            from: NSRange(location: 0, length: source.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        pasteboard.setData(data, forType: .rtf)

        let result = ClipboardPinContentReader.render(from: pasteboard)

        guard case let .image(image) = result else {
            Issue.record("Expected rendered RTF content, got \(result)")
            return
        }
        #expect(image.height > 400)
    }

    @Test("reads RTFD clipboard content")
    @MainActor
    func readsRTFD() throws {
        let pasteboard = makePasteboard()
        let source = NSAttributedString(string: "RTFD content")
        let data = try source.data(
            from: NSRange(location: 0, length: source.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )
        pasteboard.setData(data, forType: .rtfd)

        let parsed = try #require(ClipboardPinContentReader.attributedText(from: pasteboard))

        #expect(parsed.string == "RTFD content")
    }

    @Test("converts HTML locally without retaining remote resources or scripts")
    @MainActor
    func convertsHTMLSafely() throws {
        let pasteboard = makePasteboard()
        pasteboard.setString(
            #"<p>Hello <strong>world</strong></p><img src="https://example.invalid/pixel.png"><p>Second &amp; third</p><script>bad()</script>"#,
            forType: .html
        )

        let text = try #require(ClipboardPinContentReader.htmlText(from: pasteboard))

        #expect(text == "Hello world\nSecond & third")
        #expect(!text.contains("https://"))
        #expect(!text.contains("bad()"))
    }

    @Test("decodes adversarial HTML entities within a bounded time")
    @MainActor
    func decodesHTMLEntitiesInLinearTime() throws {
        let pasteboard = makePasteboard()
        let html = "<p>\(String(repeating: "&", count: 50_000));</p>"
        pasteboard.setString(html, forType: .html)
        let clock = ContinuousClock()

        let duration = try clock.measure {
            _ = try #require(ClipboardPinContentReader.htmlText(from: pasteboard))
        }

        #expect(duration < .seconds(1))
    }

    @Test("describes every copied file instead of choosing the first one")
    @MainActor
    func describesFileLists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapsoClipboardPinTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("notes.txt")
        let second = directory.appendingPathComponent("archive.zip")
        try Data("notes".utf8).write(to: first)
        try Data("archive".utf8).write(to: second)
        let pasteboard = makePasteboard()
        pasteboard.writeObjects([first as NSURL, second as NSURL])

        let text = try #require(ClipboardPinContentReader.fileListText(from: pasteboard))

        #expect(text.contains("notes.txt"))
        #expect(text.contains("archive.zip"))
        #expect(text.contains(first.path))
        #expect(text.contains(second.path))

        guard case .image = ClipboardPinContentReader.render(from: pasteboard) else {
            Issue.record("Expected the copied file list to render as a pin image")
            return
        }
    }

    @Test("loads an image from a copied plain file path")
    @MainActor
    func loadsImagePathString() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapsoClipboardPin-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try makeImage(width: 13, height: 9)
        let data = try #require(NSBitmapImageRep(cgImage: source).representation(using: .png, properties: [:]))
        try data.write(to: url)
        let pasteboard = makePasteboard()
        pasteboard.setString(url.path, forType: .string)

        let result = ClipboardPinContentReader.render(from: pasteboard)

        guard case let .image(image) = result else {
            Issue.record("Expected the copied image path to load, got \(result)")
            return
        }
        #expect(image.width == 13)
        #expect(image.height == 9)
    }

    @Test("does not open arbitrary file paths as images")
    @MainActor
    func rejectsUnsupportedImagePathExtension() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapsoClipboardPin-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try makeImage(width: 13, height: 9)
        let data = try #require(NSBitmapImageRep(cgImage: source).representation(using: .png, properties: [:]))
        try data.write(to: url)
        let pasteboard = makePasteboard()
        pasteboard.setString(url.path, forType: .string)

        let result = ClipboardPinContentReader.render(from: pasteboard)

        guard case let .image(image) = result else {
            Issue.record("Expected the path to render as text, got \(result)")
            return
        }
        #expect(image.width >= 320)
        #expect(image.height >= 100)
    }

    @Test("rejects oversized text clipboard content")
    @MainActor
    func rejectsOversizedText() {
        let pasteboard = makePasteboard()
        pasteboard.setString(String(repeating: "x", count: 100_001), forType: .string)

        let result = ClipboardPinContentReader.render(from: pasteboard)

        guard case .tooLarge = result else {
            Issue.record("Expected oversized clipboard content, got \(result)")
            return
        }
    }

    @Test("renders plain text clipboard content as a pin image")
    @MainActor
    func rendersPlainText() throws {
        let pasteboard = makePasteboard()
        pasteboard.setString("First line\nSecond line", forType: .string)

        let result = ClipboardPinContentReader.render(
            from: pasteboard,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        guard case let .image(image) = result else {
            Issue.record("Expected a rendered pin image, got \(result)")
            return
        }
        #expect(image.width >= 300)
        #expect(image.height >= 100)
        #expect(image.colorSpace?.name == CGColorSpace.sRGB)
        #expect(image.bitsPerComponent == 8)
    }

    private func makePasteboard() -> NSPasteboard {
        let name = NSPasteboard.Name("CapsoClipboardPinContentReaderTests.\(UUID().uuidString)")
        let pasteboard = NSPasteboard(name: name)
        pasteboard.clearContents()
        return pasteboard
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func rgbaPixel(in image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        #expect(image.bitsPerPixel == 32)
        let data = try #require(image.dataProvider?.data as Data?)
        let offset = y * image.bytesPerRow + x * 4
        return Array(data[offset..<(offset + 4)])
    }
}
