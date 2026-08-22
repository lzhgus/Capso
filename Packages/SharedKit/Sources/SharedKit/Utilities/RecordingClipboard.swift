import AppKit

public enum RecordingClipboard {
    /// Copies a finished recording as a file URL so it can be pasted into apps
    /// that accept video or GIF attachments.
    @discardableResult
    public static func copy(
        fileURL: URL,
        cleaningDirectory directory: URL? = nil,
        fileManager: FileManager = .default,
        pasteboard: NSPasteboard = .general,
        write: ((NSPasteboard, URL) -> Bool)? = nil
    ) -> Bool {
        guard fileURL.isFileURL,
              fileManager.isReadableFile(atPath: fileURL.path) else {
            return false
        }

        let wrote: Bool
        if let write {
            wrote = write(pasteboard, fileURL)
        } else {
            pasteboard.clearContents()
            wrote = pasteboard.writeObjects([fileURL as NSURL])
        }
        guard wrote else {
            try? fileManager.removeItem(at: fileURL)
            return false
        }

        if let directory,
           let files = try? fileManager.contentsOfDirectory(
               at: directory,
               includingPropertiesForKeys: nil
           ) {
            let currentURL = fileURL.resolvingSymlinksInPath()
            for staleURL in files
            where staleURL.resolvingSymlinksInPath() != currentURL {
                try? fileManager.removeItem(at: staleURL)
            }
        }
        return true
    }
}
