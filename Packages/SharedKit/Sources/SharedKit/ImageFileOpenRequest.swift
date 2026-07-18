// Packages/SharedKit/Sources/SharedKit/ImageFileOpenRequest.swift
import Foundation

public enum ImageFileOpenRequest {
    public static func partition(urls: [URL]) -> (imageFiles: [URL], remainder: [URL]) {
        var imageFiles: [URL] = []
        var remainder: [URL] = []
        for url in urls {
            if ImageFileReader.isSupported(url) {
                imageFiles.append(url)
            } else {
                remainder.append(url)
            }
        }
        return (imageFiles, remainder)
    }
}

public struct ImageFileOpenBuffer: Sendable {
    private var pendingURLs: [URL]?

    public init() {}

    public mutating func enqueue(_ urls: [URL]) {
        if let existing = pendingURLs {
            pendingURLs = existing + urls
        } else {
            pendingURLs = urls
        }
    }

    public mutating func takeIfReady(coordinatorIsReady: Bool) -> [URL]? {
        guard coordinatorIsReady, let urls = pendingURLs else { return nil }
        pendingURLs = nil
        return urls
    }
}
