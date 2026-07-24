import AppKit
import CoreGraphics

public enum ClipboardImageReader {
    public static func image(from pasteboard: NSPasteboard = .general) -> CGImage? {
        fileURLImage(from: pasteboard)
            ?? objectImage(from: pasteboard)
            ?? dataImage(from: pasteboard)
    }

    private static func fileURLImage(from pasteboard: NSPasteboard) -> CGImage? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        guard let url = urls?.first(where: { $0.isFileURL }) else {
            return nil
        }
        return ImageFileReader.image(at: url)
    }

    private static func objectImage(from pasteboard: NSPasteboard) -> CGImage? {
        let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]
        guard let image = images?.first else { return nil }
        return ImageUtilities.cgImage(from: image)
    }

    private static func dataImage(from pasteboard: NSPasteboard) -> CGImage? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            guard let data = pasteboard.data(forType: type),
                  let image = NSImage(data: data),
                  let cgImage = ImageUtilities.cgImage(from: image) else {
                continue
            }
            return cgImage
        }
        return nil
    }
}
