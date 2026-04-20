// Packages/EditorKit/Tests/EditorKitTests/FrameCompositorTests.swift

import Testing
import Foundation
import CoreImage
import CoreGraphics
@testable import EditorKit

@Suite("FrameCompositor")
struct FrameCompositorTests {

    private func makeTestImage(width: Int = 1920, height: Int = 1080, color: CIColor = .red) -> CIImage {
        CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    @Test("Identity transform returns image with same dimensions")
    func identityTransform() {
        let source = makeTestImage()
        let compositor = FrameCompositor(
            sourceSize: CGSize(width: 1920, height: 1080),
            backgroundStyle: BackgroundStyle(enabled: false),
            outputScale: 1.0
        )
        let result = compositor.compose(frame: source, zoomTransform: .identity, cursorPosition: nil, cursorImage: nil)
        #expect(result.extent.width == 1920)
        #expect(result.extent.height == 1080)
    }

    @Test("Zoom transform produces same-size output")
    func zoomTransform() {
        let source = makeTestImage()
        let compositor = FrameCompositor(
            sourceSize: CGSize(width: 1920, height: 1080),
            backgroundStyle: BackgroundStyle(enabled: false),
            outputScale: 1.0
        )
        // translateX/Y = focus point in normalized 0-1 coords; 0.5 = center
        let zoom = FrameTransform(scale: 2.0, translateX: 0.5, translateY: 0.5)
        let result = compositor.compose(frame: source, zoomTransform: zoom, cursorPosition: nil, cursorImage: nil)
        #expect(result.extent.width == 1920)
        #expect(result.extent.height == 1080)
    }

    @Test("Background enabled produces larger output with padding")
    func backgroundWithPadding() {
        let source = makeTestImage(width: 1920, height: 1080)
        let style = BackgroundStyle(enabled: true, padding: 40, cornerRadius: 12, shadowEnabled: false, shadowRadius: 0, shadowOpacity: 0)
        let compositor = FrameCompositor(sourceSize: CGSize(width: 1920, height: 1080), backgroundStyle: style, outputScale: 1.0)
        let result = compositor.compose(frame: source, zoomTransform: .identity, cursorPosition: nil, cursorImage: nil)
        #expect(result.extent.width == 2000)
        #expect(result.extent.height == 1160)
    }

    @Test("Background disabled returns source dimensions")
    func backgroundDisabled() {
        let source = makeTestImage(width: 800, height: 600)
        let style = BackgroundStyle(enabled: false, padding: 40)
        let compositor = FrameCompositor(sourceSize: CGSize(width: 800, height: 600), backgroundStyle: style, outputScale: 1.0)
        let result = compositor.compose(frame: source, zoomTransform: .identity, cursorPosition: nil, cursorImage: nil)
        #expect(result.extent.width == 800)
        #expect(result.extent.height == 600)
    }

    @Test("Output dimensions are even numbers for video encoding")
    func evenDimensions() {
        let source = makeTestImage(width: 801, height: 601)
        let style = BackgroundStyle(enabled: true, padding: 15)
        let compositor = FrameCompositor(sourceSize: CGSize(width: 801, height: 601), backgroundStyle: style, outputScale: 1.0)
        let result = compositor.compose(frame: source, zoomTransform: .identity, cursorPosition: nil, cursorImage: nil)
        #expect(Int(result.extent.width) % 2 == 0)
        #expect(Int(result.extent.height) % 2 == 0)
    }

    @Test("Output size is computed correctly")
    func outputSizeComputation() {
        let style = BackgroundStyle(enabled: true, padding: 20)
        let compositor = FrameCompositor(sourceSize: CGSize(width: 1920, height: 1080), backgroundStyle: style, outputScale: 1.0)
        let size = compositor.outputSize
        #expect(size.width == 1960)
        #expect(size.height == 1120)
    }

    @Test("Output size without background equals source size")
    func outputSizeNoBackground() {
        let style = BackgroundStyle(enabled: false)
        let compositor = FrameCompositor(sourceSize: CGSize(width: 1920, height: 1080), backgroundStyle: style, outputScale: 1.0)
        let size = compositor.outputSize
        #expect(size.width == 1920)
        #expect(size.height == 1080)
    }
}
