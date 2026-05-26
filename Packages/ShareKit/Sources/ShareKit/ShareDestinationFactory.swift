import Foundation

public enum ShareDestinationFactory {
    public static func make(config: ShareConfig, accessKey: String, secretKey: String) throws -> any ShareDestination {
        try config.validateForUpload()
        guard !accessKey.isEmpty, !secretKey.isEmpty else {
            throw ShareError.notConfigured
        }

        switch config.provider {
        case .r2:
            return R2Destination(config: config, accessKey: accessKey, secretKey: secretKey)
        case .s3:
            return S3Destination(config: config, accessKey: accessKey, secretKey: secretKey)
        case .tencentCOS:
            return TencentCOSDestination(config: config, secretID: accessKey, secretKey: secretKey)
        case .aliyunOSS:
            return AliyunOSSDestination(config: config, accessKeyID: accessKey, accessKeySecret: secretKey)
        }
    }
}

public extension ShareDestination {
    func validateConfig() async throws {
        let testID = IDGenerator.shortID()
        let testKey = "_capso_test_\(testID).txt"
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent(testKey)
        try "ok".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let publicURL = try await upload(file: tmpFile, key: testKey, contentType: "text/plain")

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
