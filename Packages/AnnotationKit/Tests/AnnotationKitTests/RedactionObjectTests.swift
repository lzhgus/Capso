import Testing
import Foundation
import CoreGraphics
@testable import AnnotationKit

@Suite("Redaction object")
struct RedactionObjectTests {
    @Test("Pixelate object copy preserves redaction mode")
    func copyPreservesRedactionMode() {
        let original = PixelateObject(
            rect: CGRect(x: 10, y: 12, width: 40, height: 30),
            blockSize: 16,
            mode: .blur
        )

        let copied = original.copy()
        guard let redactionCopy = copied as? PixelateObject else {
            Issue.record("copy() did not return PixelateObject")
            return
        }

        #expect(redactionCopy.id != original.id)
        #expect(redactionCopy.rect == original.rect)
        #expect(redactionCopy.blockSize == original.blockSize)
        #expect(redactionCopy.mode == .blur)
    }

    @Test("Solid redaction renders a flat filled region")
    func solidRedactionRendersFill() throws {
        let source = try makeTestImage(width: 8, height: 8, color: CGColor(gray: 1, alpha: 1))
        let redaction = PixelateObject(
            rect: CGRect(x: 2, y: 2, width: 4, height: 4),
            blockSize: 12,
            mode: .solid
        )
        redaction.style = StrokeStyle(color: .black, lineWidth: 1, opacity: 1)

        let rendered = try #require(AnnotationRenderer.render(sourceImage: source, objects: [redaction]))

        #expect(sampleRGBA(rendered, x: 3, y: 3) == RGBA(r: 0, g: 0, b: 0, a: 255))
        #expect(sampleRGBA(rendered, x: 0, y: 0) == RGBA(r: 255, g: 255, b: 255, a: 255))
    }

    @Test("Blur redaction changes source pixels inside the selected region")
    func blurRedactionChangesInteriorPixels() throws {
        let source = try makeSplitImage(width: 16, height: 16)
        let redaction = PixelateObject(
            rect: CGRect(x: 4, y: 4, width: 8, height: 8),
            blockSize: 12,
            mode: .blur
        )

        let rendered = try #require(AnnotationRenderer.render(sourceImage: source, objects: [redaction]))

        #expect(sampleRGBA(rendered, x: 7, y: 7) != sampleRGBA(source, x: 7, y: 7))
        #expect(sampleRGBA(rendered, x: 1, y: 1) == sampleRGBA(source, x: 1, y: 1))
    }

    @Test("Pixelate redaction renders repeated block pixels")
    func pixelateRedactionRendersBlockPixels() throws {
        let source = try makeHorizontalGradientImage(width: 16, height: 16)
        let redaction = PixelateObject(
            rect: CGRect(x: 0, y: 0, width: 16, height: 16),
            blockSize: 4,
            mode: .pixelate
        )

        let rendered = try #require(AnnotationRenderer.render(sourceImage: source, objects: [redaction]))

        #expect(sampleRGBA(rendered, x: 1, y: 8) == sampleRGBA(rendered, x: 6, y: 8))
        #expect(sampleRGBA(rendered, x: 1, y: 8) != sampleRGBA(rendered, x: 10, y: 8))
    }

    @Test("Pixelate samples the selected top-left source region")
    func pixelateSamplesSelectedTopLeftSourceRegion() throws {
        let source = try makeQuadrantImage(width: 16, height: 16)
        let redaction = PixelateObject(
            rect: CGRect(x: 0, y: 0, width: 8, height: 8),
            blockSize: 4,
            mode: .pixelate
        )

        let rendered = try #require(AnnotationRenderer.render(sourceImage: source, objects: [redaction]))
        let sampled = sampleRGBA(rendered, x: 3, y: 3)

        #expect(sampled.r > 200)
        #expect(sampled.b < 80)
    }

    @Test("Pixelate samples the selected top-right source region")
    func pixelateSamplesSelectedTopRightSourceRegion() throws {
        let source = try makeQuadrantImage(width: 16, height: 16)
        let redaction = PixelateObject(
            rect: CGRect(x: 8, y: 0, width: 8, height: 8),
            blockSize: 4,
            mode: .pixelate
        )

        let rendered = try #require(AnnotationRenderer.render(sourceImage: source, objects: [redaction]))
        let sampled = sampleRGBA(rendered, x: 11, y: 3)

        #expect(sampled.g > 180)
        #expect(sampled.r < 100)
        #expect(sampled.b < 100)
    }

    @Test("Pixelate draws inside the selected region in a flipped scaled canvas")
    func pixelateDrawsInsideSelectedRegionInFlippedScaledCanvas() throws {
        let source = try makeQuadrantImage(width: 16, height: 16)
        let redaction = PixelateObject(
            rect: CGRect(x: 8, y: 0, width: 8, height: 8),
            blockSize: 4,
            mode: .pixelate
        )

        let rendered = try #require(renderFlippedCanvas(source: source, objects: [redaction], zoomScale: 2))
        let sampled = sampleRGBA(rendered, x: 22, y: 6)

        #expect(sampled.g > 180)
        #expect(sampled.r < 100)
        #expect(sampled.b < 100)
    }
}

private struct RGBA: Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8
}

private func makeTestImage(width: Int, height: Int, color: CGColor) throws -> CGImage {
    let context = try #require(makeBitmapContext(width: width, height: height))
    context.setFillColor(color)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

private func makeSplitImage(width: Int, height: Int) throws -> CGImage {
    let context = try #require(makeBitmapContext(width: width, height: height))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
    return try #require(context.makeImage())
}

private func makeHorizontalGradientImage(width: Int, height: Int) throws -> CGImage {
    let context = try #require(makeBitmapContext(width: width, height: height))
    for x in 0..<width {
        let gray = CGFloat(x) / CGFloat(max(1, width - 1))
        context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: x, y: 0, width: 1, height: height))
    }
    return try #require(context.makeImage())
}

private func makeQuadrantImage(width: Int, height: Int) throws -> CGImage {
    let context = try #require(makeBitmapContext(width: width, height: height))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height / 2))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))
    context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    context.fill(CGRect(x: width / 2, y: height / 2, width: width / 2, height: height / 2))
    return try #require(context.makeImage())
}

private func makeBitmapContext(width: Int, height: Int) -> CGContext? {
    CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}

private func renderFlippedCanvas(
    source: CGImage,
    objects: [any AnnotationObject],
    zoomScale: CGFloat
) -> CGImage? {
    let width = Int(CGFloat(source.width) * zoomScale)
    let height = Int(CGFloat(source.height) * zoomScale)
    guard let context = makeBitmapContext(width: width, height: height) else { return nil }

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.scaleBy(x: zoomScale, y: zoomScale)

    let imageRect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
    context.saveGState()
    context.translateBy(x: 0, y: CGFloat(source.height))
    context.scaleBy(x: 1, y: -1)
    context.draw(source, in: imageRect)
    context.restoreGState()

    for object in objects {
        if let pixelate = object as? PixelateObject {
            pixelate.renderWithSource(in: context, sourceImage: source)
        } else {
            object.render(in: context)
        }
    }

    return context.makeImage()
}

private func sampleRGBA(_ image: CGImage, x: Int, y: Int) -> RGBA {
    let context = makeBitmapContext(width: 1, height: 1)!
    context.draw(
        image,
        in: CGRect(
            x: -x,
            y: -(image.height - 1 - y),
            width: image.width,
            height: image.height
        )
    )
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    return RGBA(r: data[0], g: data[1], b: data[2], a: data[3])
}
