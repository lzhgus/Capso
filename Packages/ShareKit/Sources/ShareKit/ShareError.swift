// Packages/ShareKit/Sources/ShareKit/ShareError.swift

public enum ShareError: Error, Equatable, Sendable {
    case notConfigured
    case invalidCredentials
    case invalidURLPrefix(reason: String)
    case network(underlying: String)
    case quotaExceeded
    case publicAccessUnreachable  // upload succeeded but public URL fetch failed
    case unknown(String)
}
