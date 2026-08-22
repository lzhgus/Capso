import Foundation

/// Tracks one finished recording's automatic clipboard copy so Save/Copy can
/// reuse the encoded file and Cloud Share can keep the last pasteboard write.
public struct RecordingClipboardState: Sendable, Equatable {
    public var copiedFileURL: URL?

    public init(copiedFileURL: URL? = nil) {
        self.copiedFileURL = copiedFileURL
    }

    public mutating func markCopied(_ url: URL) {
        copiedFileURL = url
    }

    public var canReuseAutomaticCopy: Bool { copiedFileURL != nil }
}
