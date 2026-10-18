import AppKit
import SharedKit

/// "Save As…" for screenshots: the user picks the name and folder each time.
@MainActor
enum ScreenshotSavePanel {
    /// Returns the written file, or nil when the user cancels or the write fails.
    static func save(
        _ image: CGImage,
        output: ScreenshotOutputOptions,
        date: Date,
        sourceAppName: String?,
        sourceWindowTitle: String?,
        template: String
    ) -> URL? {
        let fileFormat = output.format.fileFormat
        let panel = NSSavePanel()
        panel.nameFieldStringValue = FileNaming.generateFileName(
            for: .screenshot,
            format: fileFormat,
            date: date,
            sourceAppName: sourceAppName,
            sourceWindowTitle: sourceWindowTitle,
            template: template
        )
        panel.allowedContentTypes = [fileFormat.contentType]
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            guard let data = ImageEncoders.default.encode(
                image, format: output.format, quality: output.quality
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: url)
            return url
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }
}
