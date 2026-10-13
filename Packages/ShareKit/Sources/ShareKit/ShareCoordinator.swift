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
    /// Read when each upload starts; when `true` the link is copied right away
    /// instead of after the upload finishes.
    private let copiesLinkWhenUploadStarts: @MainActor () -> Bool
    private var uploadQueue: [UploadRequest] = []
    private var isProcessingQueue = false

    private struct UploadRequest {
        let file: URL
        let contentType: String
        let continuation: CheckedContinuation<URL, Error>
    }

    public init(destination: ShareDestination, copiesLinkWhenUploadStarts: @escaping @MainActor () -> Bool = { false }) {
        self.destination = destination
        self.copiesLinkWhenUploadStarts = copiesLinkWhenUploadStarts
    }

    /// Uploads `file` and copies its URL to the clipboard — on success, or as soon
    /// as the upload starts when `copiesLinkWhenUploadStarts` says so.
    /// Returns the URL on success; throws on failure. Updates `state` for observers.
    /// Clipboard is **never** written on failure.
    @discardableResult
    public func upload(file: URL, contentType: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            uploadQueue.append(
                UploadRequest(
                    file: file,
                    contentType: contentType,
                    continuation: continuation
                )
            )
            guard !isProcessingQueue else { return }
            isProcessingQueue = true
            Task { await processUploadQueue() }
        }
    }

    private func processUploadQueue() async {
        defer { isProcessingQueue = false }

        while !uploadQueue.isEmpty {
            let request = uploadQueue.removeFirst()
            state = .uploading
            let id = IDGenerator.shortID()
            let ext = request.file.pathExtension
            let key = ext.isEmpty ? id : "\(id).\(ext)"
            let copiedEarly = copiesLinkWhenUploadStarts()
            if copiedEarly {
                copyToClipboard(destination.publicURL(for: key))
            }

            do {
                let url = try await destination.upload(
                    file: request.file,
                    key: key,
                    contentType: request.contentType
                )
                state = .succeeded(url)
                if !copiedEarly { copyToClipboard(url) }
                request.continuation.resume(returning: url)
            } catch let error as ShareError {
                state = .failed(error)
                request.continuation.resume(throwing: error)
            } catch {
                let mapped = ShareError.unknown(error.localizedDescription)
                state = .failed(mapped)
                request.continuation.resume(throwing: mapped)
            }
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
