// Packages/ShareKit/Sources/ShareKit/ShareDestination.swift

import Foundation

/// Abstracts over a "place that captures can be uploaded to and shared from".
/// Conformances are responsible for: authenticating to the backend, writing the
/// file's bytes, and returning a URL that resolves over HTTPS GET with no auth
/// required (the captured asset must be publicly readable). Conformances must be
/// safe to call from any actor, hence the `Sendable` requirement.
public protocol ShareDestination: Sendable {
    /// Upload `file` under `key` and return the public URL.
    func upload(file: URL, key: String, contentType: String) async throws -> URL

    /// Delete an object by key. No-op if it doesn't exist.
    func delete(key: String) async throws

    /// Round-trip test: upload tiny file, fetch via public URL, delete.
    /// Throws if any step fails.
    func validateConfig() async throws
}
