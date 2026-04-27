// Packages/ShareKit/Sources/ShareKit/ShareCoordinator.swift

import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

public enum UploadState: Sendable {
    case idle
    case uploading
    case succeeded(URL)
    case failed(ShareError)
}

@MainActor
@Observable
public final class ShareCoordinator {
    public private(set) var state: UploadState = .idle
    public let destination: ShareDestination
    private var isInFlight = false

    public init(destination: ShareDestination) {
        self.destination = destination
    }

    /// Uploads `file`, copies the resulting URL to clipboard on success.
    /// Returns the URL on success; throws on failure. Updates `state` for observers.
    /// Clipboard is **never** written on failure.
    @discardableResult
    public func upload(file: URL, contentType: String) async throws -> URL {
        guard !isInFlight else {
            throw ShareError.unknown("Upload already in progress")
        }
        isInFlight = true
        defer { isInFlight = false }

        state = .uploading
        let id = IDGenerator.shortID()
        let ext = file.pathExtension
        let key = ext.isEmpty ? id : "\(id).\(ext)"

        do {
            let url = try await destination.upload(file: file, key: key, contentType: contentType)
            state = .succeeded(url)
            copyToClipboard(url)
            return url
        } catch let err as ShareError {
            state = .failed(err)
            throw err
        } catch {
            let mapped = ShareError.unknown(error.localizedDescription)
            state = .failed(mapped)
            throw mapped
        }
    }

    public func reset() {
        state = .idle
    }

    private func copyToClipboard(_ url: URL) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #endif
    }
}
