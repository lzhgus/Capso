import CoreGraphics
import Foundation
import Testing
@testable import CaptureKit

/// Runs frames of a synthetic page with a sticky header, a sticky footer and a
/// moving scrollbar thumb through the same detection, matching and stitching
/// steps as `ScrollCaptureController`, and compares against the real page.
@Suite("Scroll capture pipeline")
struct ScrollCapturePipelineTests {
    private let width = 400
    private let header = 60
    private let footer = 40
    private let viewport = 500
    private let scrollbar = 10
    private let page: [UInt8]
    private let pageHeight = 2400

    init() {
        var seed: UInt64 = 7
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(seed >> 33)
        }
        // Random coloured blocks so every part of the page is distinctive.
        var pixels = [UInt8](repeating: 255, count: width * pageHeight * 4)
        for _ in 0..<(pageHeight / 2) {
            let (x, y) = (next() % (width - scrollbar), next() % pageHeight)
            let (w, h) = (8 + next() % 90, 3 + next() % 16)
            let color = [UInt8(next() % 256), UInt8(next() % 256), UInt8(next() % 256)]
            for row in y..<min(y + h, pageHeight) {
                for col in x..<min(x + w, width - scrollbar) {
                    let i = (row * width + col) * 4
                    pixels[i] = color[0]; pixels[i + 1] = color[1]; pixels[i + 2] = color[2]
                }
            }
        }
        page = pixels
    }

    /// The window as it looks when the page is scrolled down by `scroll` rows.
    private func frame(scrolledTo scroll: Int) -> CGImage {
        let height = header + viewport + footer
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for col in 0..<width {
                let i = (row * width + col) * 4
                let color: [UInt8]
                if row < header {
                    color = [30, 60, 200]
                } else if row >= header + viewport {
                    color = [200, 40, 40]
                } else if col >= width - scrollbar {
                    let thumbTop = header + scroll * viewport / pageHeight
                    color = (thumbTop..<thumbTop + 80).contains(row) ? [90, 90, 90] : [240, 240, 240]
                } else {
                    let p = ((scroll + row - header) * width + col) * 4
                    color = [page[p], page[p + 1], page[p + 2]]
                }
                pixels[i] = color[0]; pixels[i + 1] = color[1]; pixels[i + 2] = color[2]; pixels[i + 3] = 255
            }
        }
        return makeImage(pixels, height: height)
    }

    private func makeImage(_ pixels: [UInt8], height: Int) -> CGImage {
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    private func rgbRows(_ image: CGImage, columns: Int) -> [[UInt8]] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = CGContext(
            data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (0..<image.height).map { row in
            (0..<columns).flatMap { col -> [UInt8] in
                let i = (row * image.width + col) * 4
                return [data[i], data[i + 1], data[i + 2]]
            }
        }
    }

    @Test("Sticky header and footer are found and ignored when matching")
    func detectsFixedRegions() throws {
        let regions = ScrollCaptureController.FixedRegions.detect(
            frame1: frame(scrolledTo: 0), frame2: frame(scrolledTo: 150)
        )
        #expect(regions.header == header)
        #expect(regions.footer == footer)

        let offset = ScrollCaptureController.verticalOffset(
            from: frame(scrolledTo: 0), to: frame(scrolledTo: 150), ignoring: regions
        )
        #expect(offset == 150)
    }

    @Test("Scrolling back up gives a negative offset")
    func upwardScrollIsNegative() {
        let regions = ScrollCaptureController.FixedRegions(header: header, footer: footer)
        let offset = ScrollCaptureController.verticalOffset(
            from: frame(scrolledTo: 400), to: frame(scrolledTo: 300), ignoring: regions
        )
        #expect(offset == -100)
    }

    @Test("Stitched page matches the real page, with header and footer once")
    func stitchedPageMatchesSource() throws {
        let positions = [0, 130, 260, 200, 390, 520, 700, 880, 1000]
        let stitcher = ScrollStitcher()
        var reference = frame(scrolledTo: positions[0])
        stitcher.setInitialFrame(reference)
        var regions: ScrollCaptureController.FixedRegions?
        var lastStitched = positions[0]

        for position in positions.dropFirst() {
            let shot = frame(scrolledTo: position)
            if regions == nil {
                regions = .detect(frame1: reference, frame2: shot)
                stitcher.setFooterHeight(regions!.footer)
            }
            guard let offset = ScrollCaptureController.verticalOffset(from: reference, to: shot, ignoring: regions!),
                  offset >= 3,
                  case .stitched = stitcher.stitch(newFrame: shot, detectedOffset: offset) else { continue }
            reference = shot
            lastStitched = position
        }

        #expect(lastStitched == positions.last)
        let result = try #require(stitcher.mergedImage)
        let expectedBodyRows = lastStitched + viewport
        #expect(result.height == header + expectedBodyRows + footer)

        let rows = rgbRows(result, columns: width - scrollbar)
        let first = rgbRows(frame(scrolledTo: 0), columns: width - scrollbar)
        #expect(Array(rows[0..<header]) == Array(first[0..<header]))
        #expect(Array(rows[(rows.count - footer)...]) == Array(first[(first.count - footer)...]))

        let pageRows = (0..<expectedBodyRows).map { row in
            (0..<(width - scrollbar)).flatMap { col -> [UInt8] in
                let i = (row * width + col) * 4
                return [page[i], page[i + 1], page[i + 2]]
            }
        }
        #expect(Array(rows[header..<(header + expectedBodyRows)]) == pageRows)
    }

    @Test("A frame with no overlap is rejected instead of leaving a gap")
    func noOverlapIsRejected() {
        let stitcher = ScrollStitcher()
        stitcher.setInitialFrame(frame(scrolledTo: 0))
        stitcher.setFooterHeight(footer)
        let result = stitcher.stitch(newFrame: frame(scrolledTo: 900), detectedOffset: header + viewport)
        guard case .alignmentFailed = result else {
            Issue.record("expected alignmentFailed, got \(result)")
            return
        }
    }
}
