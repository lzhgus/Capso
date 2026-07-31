import Foundation

public actor R2Destination: ShareDestination {
    private let config: ShareConfig
    private let accessKey: String
    private let secretKey: String

    public init(config: ShareConfig, accessKey: String, secretKey: String) {
        self.config = config
        self.accessKey = accessKey
        self.secretKey = secretKey
    }

    public func upload(file: URL, key: String, contentType: String) async throws -> URL {
        let objectKey = config.objectKey(for: key)
        let target = S3CompatibleHTTP.r2Target(
            accountID: config.accountID,
            bucket: config.bucket,
            objectKey: objectKey
        )
        // R2 ignores region for routing; SigV4 still requires a region string.
        try await S3CompatibleHTTP.putObject(
            file: file,
            target: target,
            region: "auto",
            accessKeyId: accessKey,
            secretAccessKey: secretKey,
            contentType: contentType
        )
        return config.publicURL(forObjectKey: objectKey)
    }

    public func delete(key: String) async throws {
        let objectKey = config.objectKey(for: key)
        let target = S3CompatibleHTTP.r2Target(
            accountID: config.accountID,
            bucket: config.bucket,
            objectKey: objectKey
        )
        try await S3CompatibleHTTP.deleteObject(
            target: target,
            region: "auto",
            accessKeyId: accessKey,
            secretAccessKey: secretKey
        )
    }

    public func validateConfig() async throws {
        let testID = IDGenerator.shortID()
        let testKey = "_capso_test_\(testID).txt"
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent(testKey)
        try "ok".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let publicURL = try await upload(file: tmpFile, key: testKey, contentType: "text/plain")

        // Round-trip: fetch via public URL to confirm public access is enabled
        var request = URLRequest(url: publicURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? await delete(key: testKey)
            throw ShareError.publicAccessUnreachable
        }
        guard String(data: data, encoding: .utf8) == "ok" else {
            try? await delete(key: testKey)
            throw ShareError.publicAccessUnreachable
        }

        try await delete(key: testKey)
    }
}
