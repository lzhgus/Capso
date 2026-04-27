// Packages/ShareKit/Sources/ShareKit/ShareConfig.swift

import Foundation

public enum ShareProvider: String, CaseIterable, Sendable {
    case r2 = "r2"
}

public struct ShareConfig: Sendable {
    public let provider: ShareProvider
    public let urlPrefix: String  // normalized: no trailing slash
    public let accountID: String  // R2 account ID
    public let bucket: String

    public init(provider: ShareProvider, urlPrefix: String, accountID: String, bucket: String) {
        self.provider = provider
        self.urlPrefix = ShareConfig.normalizePrefix(urlPrefix)
        self.accountID = accountID
        self.bucket = bucket
    }

    /// Compose a public URL from a prefix, ID, and file extension.
    /// - Precondition: `prefix` has passed `validatePrefix(_:)`. Calling this with an
    ///   unvalidated user-supplied prefix can crash on the force-unwrap.
    public static func composePublicURL(prefix: String, id: String, ext: String) -> URL {
        let normalized = normalizePrefix(prefix)
        return URL(string: "\(normalized)/\(id).\(ext)")!
    }

    public static func normalizePrefix(_ prefix: String) -> String {
        var result = prefix
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    public static func validatePrefix(_ prefix: String) throws {
        guard prefix.hasPrefix("https://") else {
            throw ShareError.invalidURLPrefix(reason: "Must start with https://")
        }
        guard let url = URL(string: prefix), let host = url.host, !host.isEmpty else {
            throw ShareError.invalidURLPrefix(reason: "Must contain a valid hostname")
        }
        guard url.query == nil, url.fragment == nil else {
            throw ShareError.invalidURLPrefix(reason: "Must not contain query string or fragment")
        }
    }
}
