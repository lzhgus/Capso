// Packages/ShareKit/Sources/ShareKit/ShareConfig.swift

import Foundation

public enum ShareProvider: String, CaseIterable, Sendable {
    case r2 = "r2"
    case s3 = "s3"
    case tencentCOS = "tencentCOS"
    case aliyunOSS = "aliyunOSS"

    public var displayName: String {
        switch self {
        case .r2:
            return "Cloudflare R2"
        case .s3:
            return "Amazon S3"
        case .tencentCOS:
            return "Tencent COS"
        case .aliyunOSS:
            return "Aliyun OSS"
        }
    }
}

public struct ShareConfig: Sendable {
    public let provider: ShareProvider
    public let urlPrefix: String  // normalized: no trailing slash
    public let bucket: String
    public let fields: [String: String]

    public init(provider: ShareProvider, urlPrefix: String, accountID: String, bucket: String) {
        self.init(
            provider: provider,
            urlPrefix: urlPrefix,
            bucket: bucket,
            fields: ["accountID": accountID]
        )
    }

    public init(provider: ShareProvider, urlPrefix: String, bucket: String, fields: [String: String]) {
        self.provider = provider
        self.urlPrefix = ShareConfig.normalizePrefix(urlPrefix)
        self.bucket = bucket
        self.fields = fields.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    public var accountID: String {
        value("accountID")
    }

    public var region: String {
        value("region")
    }

    public var endpoint: String? {
        nonEmpty("endpoint")
    }

    public var pathPrefix: String? {
        nonEmpty("pathPrefix")
    }

    public func value(_ key: String) -> String {
        fields[key] ?? ""
    }

    public func nonEmpty(_ key: String) -> String? {
        let raw = value(key).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    public func validateForUpload() throws {
        try ShareConfig.validatePrefix(urlPrefix)
        guard !bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ShareError.notConfigured
        }
        for key in provider.requiredFields {
            guard nonEmpty(key) != nil else {
                throw ShareError.notConfigured
            }
        }
    }

    public func objectKey(for key: String) -> String {
        ShareConfig.normalizePathPrefix(pathPrefix) + key
    }

    public func publicURL(forObjectKey key: String) -> URL {
        let encoded = ShareConfig.encodeObjectKey(key)
        return URL(string: "\(urlPrefix)/\(encoded)")!
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

    public static func normalizePathPrefix(_ raw: String?) -> String {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return ""
        }
        while value.hasPrefix("/") {
            value.removeFirst()
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value.isEmpty ? "" : "\(value)/"
    }

    public static func encodeObjectKey(_ key: String) -> String {
        key.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).sharePercentEncoded() }
            .joined(separator: "/")
    }
}

private extension ShareProvider {
    var requiredFields: [String] {
        switch self {
        case .r2:
            return ["accountID"]
        case .s3, .tencentCOS, .aliyunOSS:
            return ["region"]
        }
    }
}

extension String {
    func sharePercentEncoded() -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
