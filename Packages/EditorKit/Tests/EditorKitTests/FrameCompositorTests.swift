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

    private func renderedBytes(_ image: CIImage, width: Int, height: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        CIContext().render(
            image,
            toBitmap: &bytes,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return bytes
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

    @Test("Blur effect changes only while active")
    func blurEffectChangesOnlyWhileActive() {
        let base = CIImage(color: .white)
            .cropped(to: CGRect(x: 0, y: 0, width: 120, height: 80))
        let centerBlock = CIImage(color: .black)
            .cropped(to: CGRect(x: 46, y: 26, width: 28, height: 28))
        let source = centerBlock.composited(over: base)
        let effect = RecordingEffectSegment(
            startTime: 1,
            endTime: 3,
            payload: .blur(
                BlurEffectPayload(
                    rect: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                    radius: 12
                )
            )
        )
        let compositor = FrameCompositor(
            sourceSize: CGSize(width: 120, height: 80),
            backgroundStyle: BackgroundStyle(enabled: false),
            outputScale: 1.0
        )

        let inactive = compositor.compose(
            frame: source,
            zoomTransform: .identity,
            cursorPosition: nil,
            cursorImage: nil,
            blurEffects: [effect],
            time: 0.5
        )
        let active = compositor.compose(
            frame: source,
            zoomTransform: .identity,
            cursorPosition: nil,
            cursorImage: nil,
            blurEffects: [effect],
            time: 2
        )

        #expect(inactive.extent == source.extent)
        #expect(active.extent == source.extent)
        #expect(
            renderedBytes(active, width: 120, height: 80) !=
                renderedBytes(inactive, width: 120, height: 80)
        )
    }
}
