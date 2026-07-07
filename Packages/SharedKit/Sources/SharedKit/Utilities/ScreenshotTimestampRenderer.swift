import AppKit
import CoreGraphics
import Foundation

public enum ScreenshotTimestampPosition: String, CaseIterable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    public var displayName: String {
        switch self {
        case .topLeft: "Top Left"
        case .top: "Top"
        case .topRight: "Top Right"
        case .right: "Right"
        case .bottomRight: "Bottom Right"
        case .bottom: "Bottom"
        case .bottomLeft: "Bottom Left"
        case .left: "Left"
        }
    }
}

public enum ScreenshotTimestampFormat: String, CaseIterable, Sendable {
    case dateTime
    case date
    case time
    case iso8601

    public var displayName: String {
        switch self {
        case .dateTime: "Date & Time"
        case .date: "Date"
        case .time: "Time"
        case .iso8601: "ISO 8601"
        }
    }

    public func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        switch self {
        case .dateTime:
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
        case .date:
            formatter.dateFormat = "yyyy-MM-dd"
        case .time:
            formatter.dateFormat = "HH:mm:ss"
        case .iso8601:
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        }
        return formatter.string(from: date)
    }
}

public struct ScreenshotTimestampOptions: Sendable {
    public static let fontSizeRange: ClosedRange<Int> = 8...72

    public var isEnabled: Bool
    public var position: ScreenshotTimestampPosition
    public var format: ScreenshotTimestampFormat
    public var colorHex: String
    public var fontSize: Int

    public init(
        isEnabled: Bool = false,
        position: ScreenshotTimestampPosition = .bottomRight,
        format: ScreenshotTimestampFormat = .dateTime,
        colorHex: String = "#FFFFFF",
        fontSize: Int = 14
    ) {
        self.isEnabled = isEnabled
        self.position = position
        self.format = format
        self.colorHex = Self.normalizedColorHex(colorHex) ?? "#FFFFFF"
        self.fontSize = min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
    }

    public static func normalizedColorHex(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.count == 6, UInt32(hex, radix: 16) != nil else { return nil }
        return "#\(hex.uppercased())"
    }
}

public enum ScreenshotTimestampRenderer {
    public static func render(
        image: CGImage,
        date: Date,
        options: ScreenshotTimestampOptions
    ) -> CGImage? {
        guard options.isEnabled else { return image }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: canvas)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }

        let font = NSFont.monospacedDigitSystemFont(ofSize: CGFloat(options.fontSize), weight: .medium)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
        shadow.shadowBlurRadius = max(2, CGFloat(options.fontSize) * 0.16)
        shadow.shadowOffset = CGSize(width: 0, height: -1)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color(from: options.colorHex),
            .shadow: shadow,
        ]
        let text = options.format.string(from: date)
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        let margin = max(8, CGFloat(options.fontSize))
        let rect = textRect(
            textSize: size,
            canvasSize: CGSize(width: width, height: height),
            margin: margin,
            position: options.position
        )
        attributed.draw(in: rect)

        return context.makeImage()
    }

    private static func textRect(
        textSize: CGSize,
        canvasSize: CGSize,
        margin: CGFloat,
        position: ScreenshotTimestampPosition
    ) -> CGRect {
        let x: CGFloat
        let y: CGFloat
        switch position {
        case .topLeft:
            x = margin
            y = canvasSize.height - margin - textSize.height
        case .top:
            x = (canvasSize.width - textSize.width) / 2
            y = canvasSize.height - margin - textSize.height
        case .topRight:
            x = canvasSize.width - margin - textSize.width
            y = canvasSize.height - margin - textSize.height
        case .right:
            x = canvasSize.width - margin - textSize.width
            y = (canvasSize.height - textSize.height) / 2
        case .bottomRight:
            x = canvasSize.width - margin - textSize.width
            y = margin
        case .bottom:
            x = (canvasSize.width - textSize.width) / 2
            y = margin
        case .bottomLeft:
            x = margin
            y = margin
        case .left:
            x = margin
            y = (canvasSize.height - textSize.height) / 2
        }
        return CGRect(
            x: max(margin, min(canvasSize.width - margin - textSize.width, x)),
            y: max(margin, min(canvasSize.height - margin - textSize.height, y)),
            width: textSize.width,
            height: textSize.height
        )
    }

    private static func color(from hex: String) -> NSColor {
        let normalized = ScreenshotTimestampOptions.normalizedColorHex(hex) ?? "#FFFFFF"
        let value = UInt32(normalized.dropFirst(), radix: 16) ?? 0xFFFFFF
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 0.96
        )
    }
}
