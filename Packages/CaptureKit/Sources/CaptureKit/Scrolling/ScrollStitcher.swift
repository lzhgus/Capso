// Packages/CaptureKit/Sources/CaptureKit/Scrolling/ScrollStitcher.swift
import CoreGraphics
import AppKit

public enum StitchResult: Sendable {
    case stitched(yOffset: Int)
    case noChange
    case reversedScroll
    case alignmentFailed
}

/// Incrementally stitches captured frames into a single tall image.
/// The offset is detected externally (by ScrollCaptureController via Vision)
/// and passed in. This class only handles the pixel compositing.
///
/// Rows inside a sticky footer are never appended while scrolling; the most
/// recent frame's footer is added once at the bottom of `mergedImage`.
public final class ScrollStitcher: @unchecked Sendable {
    private var body: CGImage?
    private var lastFrame: CGImage?
    private var footerHeight = 0
    private(set) var totalHeight: Int = 0

    public init() {}

    /// The stitched page including the sticky footer, if any.
    var mergedImage: CGImage? {
        guard let body else { return nil }
        guard footerHeight > 0, let lastFrame,
              let footer = lastFrame.cropping(to: CGRect(
                  x: 0, y: lastFrame.height - footerHeight,
                  width: lastFrame.width, height: footerHeight
              )) else { return body }
        return Self.stack(top: body, bottom: footer)
    }

    public func setInitialFrame(_ frame: CGImage) {
        body = frame
        lastFrame = frame
        footerHeight = 0
        totalHeight = frame.height
    }

    /// Excludes the bottom `height` rows of every frame from the stitched body.
    func setFooterHeight(_ height: Int) {
        guard let body, height > 0, height < body.height else { return }
        footerHeight = height
        self.body = body.cropping(to: CGRect(x: 0, y: 0, width: body.width, height: body.height - height))
    }

    /// Stitch a new frame that is scrolled `detectedOffset` pixel rows further down.
    public func stitch(newFrame: CGImage, detectedOffset: Int) -> StitchResult {
        guard let body else {
            setInitialFrame(newFrame)
            return .stitched(yOffset: 0)
        }
        guard detectedOffset > 0 else { return detectedOffset < 0 ? .reversedScroll : .noChange }

        let contentBottom = newFrame.height - footerHeight
        guard detectedOffset < contentBottom,
              let newRows = newFrame.cropping(to: CGRect(
                  x: 0, y: contentBottom - detectedOffset,
                  width: newFrame.width, height: detectedOffset
              )),
              let stacked = Self.stack(top: body, bottom: newRows) else {
            return .alignmentFailed
        }

        self.body = stacked
        lastFrame = newFrame
        totalHeight = stacked.height + footerHeight
        return .stitched(yOffset: detectedOffset)
    }

    private static func stack(top: CGImage, bottom: CGImage) -> CGImage? {
        let width = top.width
        let height = top.height + bottom.height
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: top.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // CGContext origin is bottom-left.
        ctx.draw(top, in: CGRect(x: 0, y: bottom.height, width: width, height: top.height))
        ctx.draw(bottom, in: CGRect(x: 0, y: 0, width: width, height: bottom.height))
        return ctx.makeImage()
    }
}
